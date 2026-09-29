#if !os(Windows)

    internal import Path
    internal import POSIX_Kernel
    internal import POSIX_Kernel_File
    @_spi(Syscall) internal import ISO_9945_Kernel_Poll

    #if canImport(Darwin)
        internal import Darwin
    #elseif canImport(Glibc)
        internal import Glibc
    #elseif canImport(Musl)
        internal import Musl
    #endif

    extension Process.Spawn {

        @usableFromInline
        internal static func _runWithCapture(
            _ configuration: Configuration
        ) throws(Process.Error) -> Process.Output {
            if configuration.stdin == .pipe {
                throw .streamPolicyUnsupported
            }

            switch (configuration.stdout, configuration.stderr) {
            case (.inherit, .inherit):
                return try _runWithoutPipes(configuration)

            case (.pipe, .inherit):
                return try _runWithStdoutPipe(configuration)

            case (.inherit, .pipe):
                return try _runWithStderrPipe(configuration)

            case (.pipe, .pipe):
                return try _runWithBothPipes(configuration)
            }
        }
    }

    extension Process.Spawn {

        @usableFromInline
        internal static func _runWithoutPipes(
            _ configuration: Configuration
        ) throws(Process.Error) -> Process.Output {
            var actions = try _makeActions()
            try _addChdir(&actions, cwd: configuration.workingDirectory)

            let pid = try _spawnWithActions(configuration, actions: actions)
            let watchdog = try _armWatchdog(pid: pid, timeout: configuration.timeout)
            let handle = Process.Handle(processID: pid)
            let status: Process.Status
            do throws(Process.Error) {
                status = try handle.wait()
            } catch {
                _disarmWatchdog(watchdog)
                throw error
            }
            _disarmWatchdog(watchdog)
            return Process.Output(status: status)
        }

        @usableFromInline
        internal static func _runWithStdoutPipe(
            _ configuration: Configuration
        ) throws(Process.Error) -> Process.Output {
            var actions = try _makeActions()
            let stdoutPipe = try _makePipe()

            do throws(ISO_9945.Kernel.Process.Error) {
                try actions.add(dup2: stdoutPipe.write, to: .stdout)
                try actions.add(close: .init(stdoutPipe.read))
            } catch {
                throw .spawn(error)
            }

            try _addChdir(&actions, cwd: configuration.workingDirectory)

            let pid = try _spawnWithActions(configuration, actions: actions)
            let stdoutRead = try _closeWriteEnd(stdoutPipe)
            let watchdog = try _armWatchdog(pid: pid, timeout: configuration.timeout)

            let captured: [UInt8]
            do throws(Process.Error) {
                captured = try _drainBytes(stdoutRead)
            } catch {
                _disarmWatchdog(watchdog)
                throw error
            }

            let handle = Process.Handle(processID: pid)
            let status: Process.Status
            do throws(Process.Error) {
                status = try handle.wait()
            } catch {
                _disarmWatchdog(watchdog)
                throw error
            }
            _disarmWatchdog(watchdog)
            return Process.Output(status: status, stdout: captured, stderr: nil)
        }

        @usableFromInline
        internal static func _runWithStderrPipe(
            _ configuration: Configuration
        ) throws(Process.Error) -> Process.Output {
            var actions = try _makeActions()
            let stderrPipe = try _makePipe()

            do throws(ISO_9945.Kernel.Process.Error) {
                try actions.add(dup2: stderrPipe.write, to: .stderr)
                try actions.add(close: .init(stderrPipe.read))
            } catch {
                throw .spawn(error)
            }

            try _addChdir(&actions, cwd: configuration.workingDirectory)

            let pid = try _spawnWithActions(configuration, actions: actions)
            let stderrRead = try _closeWriteEnd(stderrPipe)
            let watchdog = try _armWatchdog(pid: pid, timeout: configuration.timeout)

            let captured: [UInt8]
            do throws(Process.Error) {
                captured = try _drainBytes(stderrRead)
            } catch {
                _disarmWatchdog(watchdog)
                throw error
            }

            let handle = Process.Handle(processID: pid)
            let status: Process.Status
            do throws(Process.Error) {
                status = try handle.wait()
            } catch {
                _disarmWatchdog(watchdog)
                throw error
            }
            _disarmWatchdog(watchdog)
            return Process.Output(status: status, stdout: nil, stderr: captured)
        }

        @usableFromInline
        internal static func _runWithBothPipes(
            _ configuration: Configuration
        ) throws(Process.Error) -> Process.Output {
            var actions = try _makeActions()
            let stdoutPipe = try _makePipe()
            let stderrPipe = try _makePipe()

            do throws(ISO_9945.Kernel.Process.Error) {
                try actions.add(dup2: stdoutPipe.write, to: .stdout)
                try actions.add(close: .init(stdoutPipe.read))
                try actions.add(dup2: stderrPipe.write, to: .stderr)
                try actions.add(close: .init(stderrPipe.read))
            } catch {
                throw .spawn(error)
            }

            try _addChdir(&actions, cwd: configuration.workingDirectory)

            let pid = try _spawnWithActions(configuration, actions: actions)
            let stdoutRead = try _closeWriteEnd(stdoutPipe)
            let stderrRead = try _closeWriteEnd(stderrPipe)
            let watchdog = try _armWatchdog(pid: pid, timeout: configuration.timeout)

            let drained: (stdout: [UInt8], stderr: [UInt8])
            do throws(Process.Error) {
                drained = try _drainConcurrently(
                    stdout: stdoutRead,
                    stderr: stderrRead
                )
            } catch {
                _disarmWatchdog(watchdog)
                throw error
            }

            let handle = Process.Handle(processID: pid)
            let status: Process.Status
            do throws(Process.Error) {
                status = try handle.wait()
            } catch {
                _disarmWatchdog(watchdog)
                throw error
            }
            _disarmWatchdog(watchdog)
            return Process.Output(
                status: status,
                stdout: drained.stdout,
                stderr: drained.stderr
            )
        }
    }

    extension Process.Spawn {
        @usableFromInline
        internal static func _makeActions() throws(Process.Error)
            -> ISO_9945.Kernel.Process.Spawn.Actions
        {
            do throws(ISO_9945.Kernel.Process.Error) {
                return try ISO_9945.Kernel.Process.Spawn.Actions()
            } catch {
                throw .spawn(error)
            }
        }

        @usableFromInline
        internal static func _makePipe() throws(Process.Error) -> ISO_9945.Kernel.Pipe.Descriptors {
            do throws(ISO_9945.Kernel.Pipe.Error) {
                return try POSIX.Kernel.Pipe.pipe()
            } catch {
                throw .capture(error.code)
            }
        }

        @usableFromInline
        internal static func _addChdir(
            _ actions: inout ISO_9945.Kernel.Process.Spawn.Actions,
            cwd: Swift.String?
        ) throws(Process.Error) {
            guard let cwd else { return }
            do throws(Path.String.Error<ISO_9945.Kernel.Process.Error>) {
                try Path.scope(cwd) {
                    (borrowed: borrowing Path.Borrowed) throws(ISO_9945.Kernel.Process.Error) in
                    try unsafe actions.add(chdir: borrowed.pointer)
                }
            } catch {
                switch error {
                case .conversion(.interiorNUL(let index)):
                    throw .invalidPath(index: index)

                case .body(let posixError):
                    throw .spawn(posixError)
                }
            }
        }

        @usableFromInline
        internal static func _spawnWithActions(
            _ configuration: Configuration,
            actions: borrowing ISO_9945.Kernel.Process.Spawn.Actions
        ) throws(Process.Error) -> ISO_9945.Kernel.Process.ID {

            let vector = try _spawnVector(configuration)
            let envp = _flattenEnvironment(configuration.environment)
            do throws(Path.String.Error<ISO_9945.Kernel.Process.Error>) {
                return try unsafe Path.scope.array(vector, envp) {
                    (
                        vectorPtr: UnsafePointer<UnsafePointer<Path.Char>?>,
                        envpPtr: UnsafePointer<UnsafePointer<Path.Char>?>
                    ) throws(ISO_9945.Kernel.Process.Error) -> ISO_9945.Kernel.Process.ID in
                    try unsafe ISO_9945.Kernel.Process.Spawn.spawn(
                        path: vectorPtr[0]!,
                        argv: vectorPtr + 1,
                        envp: envpPtr,
                        actions: actions
                    )
                }
            } catch {
                switch error {
                case .conversion(.interiorNUL(let index)):
                    throw .invalidPath(index: _spawnVectorIndex(index))

                case .body(let posixError):
                    throw .spawn(posixError)
                }
            }
        }

        @usableFromInline
        internal static func _closeErrorCode(
            _ error: ISO_9945.Kernel.Close.Error
        ) -> Error::Error.Code {
            switch error {
            case .handle(let e): return e.code
            case .platform(let e): return e.code
            }
        }

        @usableFromInline
        internal static func _closeWriteEnd(
            _ pipe: consuming ISO_9945.Kernel.Pipe.Descriptors
        ) throws(Process.Error) -> ISO_9945.Kernel.Descriptor {
            do throws(ISO_9945.Kernel.Close.Error) {
                return try ISO_9945.Kernel.Pipe.Close.write(pipe)
            } catch {
                throw .capture(_closeErrorCode(error))
            }
        }

        @usableFromInline
        internal static func _drainBytes(
            _ descriptor: consuming ISO_9945.Kernel.Descriptor
        ) throws(Process.Error) -> [UInt8] {
            do throws(ISO_9945.Kernel.IO.Read.Error) {
                return try _drain(descriptor)
            } catch {
                throw .capture(error.code)
            }
        }

        @usableFromInline
        internal static func _drain(
            _ descriptor: consuming ISO_9945.Kernel.Descriptor
        ) throws(ISO_9945.Kernel.IO.Read.Error) -> [UInt8] {
            var buffer: [UInt8] = []
            var chunk = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = try chunk.withUnsafeMutableBufferPointer {
                    (
                        raw: inout UnsafeMutableBufferPointer<UInt8>
                    ) throws(ISO_9945.Kernel.IO.Read.Error) -> Int in
                    let bytes = UnsafeMutableRawBufferPointer(raw)
                    return try unsafe POSIX.Kernel.IO.Read.read(descriptor, into: bytes)
                }
                if n == 0 { break }
                buffer.append(contentsOf: chunk.prefix(n))
            }
            return buffer
        }
    }

    extension Process.Spawn {

        @usableFromInline
        internal static func _drainConcurrently(
            stdout stdoutDescriptor: consuming ISO_9945.Kernel.Descriptor,
            stderr stderrDescriptor: consuming ISO_9945.Kernel.Descriptor
        ) throws(Process.Error) -> (stdout: [UInt8], stderr: [UInt8]) {
            var stdoutBuffer: [UInt8] = []
            var stderrBuffer: [UInt8] = []
            var chunk = [UInt8](repeating: 0, count: 4096)

            var stdoutDone = false
            var stderrDone = false

            while !(stdoutDone && stderrDone) {
                var entries: [ISO_9945.Kernel.Poll.Entry] = []
                entries.reserveCapacity(2)
                entries.append(
                    ISO_9945.Kernel.Poll.Entry(
                        stdoutDescriptor,
                        requested: [.input]
                    )
                )
                entries.append(
                    ISO_9945.Kernel.Poll.Entry(
                        stderrDescriptor,
                        requested: [.input]
                    )
                )

                if stdoutDone { (entries[0].descriptor = -1) }
                if stderrDone { (entries[1].descriptor = -1) }

                do throws(Error.Error) {
                    _ = try POSIX.Kernel.Poll.poll(&entries, timeout: -1)
                } catch {
                    throw .capture(error.code)
                }

                if !stdoutDone, !entries[0].returned.isEmpty {
                    let n: Int
                    do throws(ISO_9945.Kernel.IO.Read.Error) {
                        n = try chunk.withUnsafeMutableBufferPointer {
                            (
                                raw: inout UnsafeMutableBufferPointer<UInt8>
                            ) throws(ISO_9945.Kernel.IO.Read.Error) -> Int in
                            let bytes = UnsafeMutableRawBufferPointer(raw)
                            return try unsafe POSIX.Kernel.IO.Read.read(
                                stdoutDescriptor,
                                into: bytes
                            )
                        }
                    } catch {
                        throw .capture(error.code)
                    }
                    if n == 0 {
                        stdoutDone = true
                    } else {
                        stdoutBuffer.append(contentsOf: chunk.prefix(n))
                    }
                }

                if !stderrDone, !entries[1].returned.isEmpty {
                    let n: Int
                    do throws(ISO_9945.Kernel.IO.Read.Error) {
                        n = try chunk.withUnsafeMutableBufferPointer {
                            (
                                raw: inout UnsafeMutableBufferPointer<UInt8>
                            ) throws(ISO_9945.Kernel.IO.Read.Error) -> Int in
                            let bytes = UnsafeMutableRawBufferPointer(raw)
                            return try unsafe POSIX.Kernel.IO.Read.read(
                                stderrDescriptor,
                                into: bytes
                            )
                        }
                    } catch {
                        throw .capture(error.code)
                    }
                    if n == 0 {
                        stderrDone = true
                    } else {
                        stderrBuffer.append(contentsOf: chunk.prefix(n))
                    }
                }
            }

            return (stdout: stdoutBuffer, stderr: stderrBuffer)
        }
    }

    extension Process.Spawn {

        @usableFromInline
        internal struct Watchdog: ~Copyable {
            @usableFromInline
            internal var thread: ISO_9945.Kernel.Thread.Handle?

            @usableFromInline
            internal var shutdownWriteFd: Int32

            @usableFromInline
            internal var shutdownReadFd: Int32

            @usableFromInline
            internal init() {
                self.thread = nil
                self.shutdownWriteFd = -1
                self.shutdownReadFd = -1
            }
        }

        @usableFromInline
        internal static func _armWatchdog(
            pid: ISO_9945.Kernel.Process.ID,
            timeout: Duration?
        ) throws(Process.Error) -> Watchdog {
            guard let timeout else {
                return Watchdog()
            }

            var fds: (Int32, Int32) = (-1, -1)
            let pipeResult: Int32 = withUnsafeMutablePointer(to: &fds) { tuple -> Int32 in
                unsafe tuple.withMemoryRebound(to: Int32.self, capacity: 2) { fdPtr -> Int32 in
                    unsafe pipe(fdPtr)
                }
            }
            guard pipeResult == 0 else {
                throw .capture(.posix(errno))
            }

            let readFd = fds.0
            let writeFd = fds.1
            let timeoutMs = _durationToPollMilliseconds(timeout)
            let pidValue: Int32 = pid.rawValue

            let thread: ISO_9945.Kernel.Thread.Handle
            do throws(ISO_9945.Kernel.Thread.Error) {
                thread = try POSIX.Kernel.Thread.create {
                    _watchdogBody(
                        shutdownReadFd: readFd,
                        pid: pidValue,
                        timeoutMilliseconds: timeoutMs
                    )
                }
            } catch {

                _closeRawFd(readFd)
                _closeRawFd(writeFd)
                throw .capture(_threadErrorCode(error))
            }

            var watchdog = Watchdog()
            watchdog.thread = consume thread
            watchdog.shutdownWriteFd = writeFd
            watchdog.shutdownReadFd = readFd
            return watchdog
        }

        @usableFromInline
        internal static func _disarmWatchdog(_ watchdog: consuming Watchdog) {

            let writeFd = watchdog.shutdownWriteFd
            let readFd = watchdog.shutdownReadFd
            let threadOpt: ISO_9945.Kernel.Thread.Handle? = consume watchdog.thread

            guard let thread = consume threadOpt else {
                return
            }

            if writeFd >= 0 {

                _writeWakeByte(writeFd)

                _closeRawFd(writeFd)
            }

            do throws(ISO_9945.Kernel.Thread.Error) {
                try thread.join()
            } catch {

            }

            if readFd >= 0 {
                _closeRawFd(readFd)
            }
        }

        @usableFromInline
        internal static func _watchdogBody(
            shutdownReadFd: Int32,
            pid: Int32,
            timeoutMilliseconds: Int32
        ) {

            var pollfdEntry = pollfd(fd: shutdownReadFd, events: Int16(POLLIN), revents: 0)
            let result: Int32 = withUnsafeMutablePointer(to: &pollfdEntry) { ptr -> Int32 in

                while true {
                    let r = unsafe poll(ptr, 1, timeoutMilliseconds)
                    if r >= 0 { return r }
                    if errno != EINTR { return r }
                }
            }

            if result == 0 {

                do throws(ISO_9945.Kernel.Process.Error) {
                    try POSIX.Kernel.Process.Kill.kill(
                        ISO_9945.Kernel.Process.ID(rawValue: pid),
                        .kill
                    )
                } catch {

                }
            }

        }

        @usableFromInline
        internal static func _writeWakeByte(_ fd: Int32) {
            var byte: UInt8 = 0
            withUnsafePointer(to: &byte) { ptr in
                _ = unsafe write(fd, ptr, 1)
            }
        }

        @usableFromInline
        internal static func _closeRawFd(_ fd: Int32) {
            _ = close(fd)
        }

        @usableFromInline
        internal static func _threadErrorCode(
            _ error: ISO_9945.Kernel.Thread.Error
        ) -> Error::Error.Code {
            switch error {
            case .create(let code): return code
            case .join(let code): return code
            case .detach(let code): return code
            case .keyCreate(let code): return code
            case .keySet(let code): return code
            }
        }

        @usableFromInline
        internal static func _durationToPollMilliseconds(_ duration: Duration) -> Int32 {
            let components = duration.components
            let attosecondsPerMs: Int64 = 1_000_000_000_000_000
            let secondsPart = components.seconds
            let attosPart = components.attoseconds

            let msFromAttos = (attosPart + attosecondsPerMs - 1) / attosecondsPerMs
            let secondsMs = secondsPart.multipliedReportingOverflow(by: 1000)
            if secondsMs.overflow { return Int32.max }
            let total = secondsMs.partialValue.addingReportingOverflow(msFromAttos)
            if total.overflow { return Int32.max }
            if total.partialValue <= 0 { return 0 }
            if total.partialValue > Int64(Int32.max) { return Int32.max }
            return Int32(total.partialValue)
        }
    }

#endif
