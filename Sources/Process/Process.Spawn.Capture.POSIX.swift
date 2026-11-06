#if !os(Windows)

    internal import Path
    internal import Kernel
    internal import POSIX_Kernel_File
    @_spi(Syscall) internal import ISO_9945_Kernel_Poll

    extension Process.Spawn {
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
        internal static func _runWithoutPipes(
            _ configuration: Configuration
        ) throws(Process.Error) -> Process.Output {
            var actions = try _makeActions()
            try _addChdir(&actions, cwd: configuration.directory)

            let pid = try _spawnWithActions(configuration, actions: &actions)
            let watchdog = try _armWatchdog(pid: pid, timeout: configuration.timeout)
            let handle = Process.Handle(id: pid)
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

            try _addChdir(&actions, cwd: configuration.directory)

            let pid = try _spawnWithActions(configuration, actions: &actions)
            let stdoutRead = try _closeWriteEnd(stdoutPipe)
            let watchdog = try _armWatchdog(pid: pid, timeout: configuration.timeout)

            let captured: [UInt8]
            do throws(Process.Error) {
                captured = try _drainBytes(stdoutRead)
            } catch {
                _disarmWatchdog(watchdog)
                throw error
            }

            let handle = Process.Handle(id: pid)
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

            try _addChdir(&actions, cwd: configuration.directory)

            let pid = try _spawnWithActions(configuration, actions: &actions)
            let stderrRead = try _closeWriteEnd(stderrPipe)
            let watchdog = try _armWatchdog(pid: pid, timeout: configuration.timeout)

            let captured: [UInt8]
            do throws(Process.Error) {
                captured = try _drainBytes(stderrRead)
            } catch {
                _disarmWatchdog(watchdog)
                throw error
            }

            let handle = Process.Handle(id: pid)
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

            try _addChdir(&actions, cwd: configuration.directory)

            let pid = try _spawnWithActions(configuration, actions: &actions)
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

            let handle = Process.Handle(id: pid)
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
        internal static func _makeActions() throws(Process.Error)
            -> ISO_9945.Kernel.Process.Spawn.Actions
        {
            do throws(ISO_9945.Kernel.Process.Error) {
                return try ISO_9945.Kernel.Process.Spawn.Actions()
            } catch {
                throw .spawn(error)
            }
        }
        internal static func _makePipe() throws(Process.Error) -> ISO_9945.Kernel.Pipe.Descriptors {
            do throws(ISO_9945.Kernel.Pipe.Error) {
                return try POSIX.Kernel.Pipe.pipe()
            } catch {
                throw .capture(error.code)
            }
        }
        internal static func _addChdir(
            _ actions: inout ISO_9945.Kernel.Process.Spawn.Actions,
            cwd: Path::Path?
        ) throws(Process.Error) {
            guard let cwd else { return }
            do throws(ISO_9945.Kernel.Process.Error) {
                try unsafe actions.add(chdir: cwd.view.pointer)
            } catch {
                throw .spawn(error)
            }
        }
        internal static func _spawnWithActions(
            _ configuration: Configuration,
            actions: inout ISO_9945.Kernel.Process.Spawn.Actions
        ) throws(Process.Error) -> ISO_9945.Kernel.Process.ID {
            let isolated: Bool
            do throws(ISO_9945.Kernel.Process.Error) {
                isolated = try actions.isolate()
            } catch {
                throw .spawn(error)
            }

            let vector = try _spawnVector(configuration)
            let envp = _flattenEnvironment(configuration.environment)
            do throws(Path.String.Error<ISO_9945.Kernel.Process.Error>) {
                return try unsafe Path.scope.array(vector, envp) {
                    (
                        vectorPtr: UnsafePointer<UnsafePointer<Path.Char>?>,
                        envpPtr: UnsafePointer<UnsafePointer<Path.Char>?>
                    ) throws(ISO_9945.Kernel.Process.Error) -> ISO_9945.Kernel.Process.ID in
                    guard let path = unsafe vectorPtr[0] else {
                        preconditionFailure("spawn vector always contains the executable path")
                    }
                    return try unsafe ISO_9945.Kernel.Process.Spawn.spawn(
                        path: path,
                        argv: vectorPtr + 1,
                        envp: envpPtr,
                        actions: actions,
                        isolated: isolated
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
        internal static func _closeErrorCode(
            _ error: ISO_9945.Kernel.Close.Error
        ) -> Error::Error.Code {
            switch error {
            case .handle(let e): return e.code
            case .platform(let e): return e.code
            }
        }
        internal static func _closeWriteEnd(
            _ pipe: consuming ISO_9945.Kernel.Pipe.Descriptors
        ) throws(Process.Error) -> ISO_9945.Kernel.Descriptor {
            do throws(ISO_9945.Kernel.Close.Error) {
                return try ISO_9945.Kernel.Pipe.Close.write(pipe)
            } catch {
                throw .capture(_closeErrorCode(error))
            }
        }
        internal static func _drainBytes(
            _ descriptor: consuming ISO_9945.Kernel.Descriptor
        ) throws(Process.Error) -> [UInt8] {
            do throws(ISO_9945.Kernel.IO.Read.Error) {
                return try _drain(descriptor)
            } catch {
                throw .capture(error.code)
            }
        }
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

                do throws(Error::Error) {
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
        internal static func _armWatchdog(
            pid: ISO_9945.Kernel.Process.ID,
            timeout: Duration?
        ) throws(Process.Error) -> Watchdog {
            guard let timeout else {
                return Watchdog()
            }

            let pipe = try _makePipe()
            let shutdown = ISO_9945.Kernel.Poll.Entry(pipe.read, requested: [.input])
            let timeoutMs = _durationToPollMilliseconds(timeout)

            let thread: ISO_9945.Kernel.Thread.Handle
            do throws(ISO_9945.Kernel.Thread.Error) {
                thread = try POSIX.Kernel.Thread.create {
                    _watchdogBody(shutdown: shutdown, pid: pid, timeoutMilliseconds: timeoutMs)
                }
            } catch {
                throw .capture(_threadErrorCode(error))
            }

            var watchdog = Watchdog()
            watchdog.thread = consume thread
            watchdog.shutdown = consume pipe
            return watchdog
        }
        internal static func _disarmWatchdog(_ watchdog: consuming Watchdog) {
            let threadOpt: ISO_9945.Kernel.Thread.Handle? = consume watchdog.thread
            let shutdownOpt: ISO_9945.Kernel.Pipe.Descriptors? = consume watchdog.shutdown

            guard let thread = consume threadOpt, let shutdown = consume shutdownOpt else {
                return
            }

            _writeWakeByte(shutdown.write)

            do throws(ISO_9945.Kernel.Thread.Error) {
                try thread.join()
            } catch {

            }
            _ = consume shutdown
        }
        internal static func _watchdogBody(
            shutdown: ISO_9945.Kernel.Poll.Entry,
            pid: ISO_9945.Kernel.Process.ID,
            timeoutMilliseconds: Int32
        ) {
            var entries = [shutdown]
            var ready = 0
            polling: while true {
                do throws(Error::Error) {
                    ready = try POSIX.Kernel.Poll.poll(&entries, timeout: timeoutMilliseconds)
                    break polling
                } catch {
                    if !error.code.isInterrupted { return }
                }
            }

            if ready == 0 {
                do throws(ISO_9945.Kernel.Process.Error) {
                    try POSIX.Kernel.Process.Kill.kill(pid, .kill)
                } catch {

                }
            }
        }
        internal static func _writeWakeByte(_ descriptor: borrowing ISO_9945.Kernel.Descriptor) {
            let byte: [UInt8] = [0]
            byte.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                do throws(ISO_9945.Kernel.IO.Write.Error) {
                    _ = try unsafe POSIX.Kernel.IO.Write.write(descriptor, from: buffer)
                } catch {

                }
            }
        }
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
