#if os(Windows)

    internal import Windows_Kernel_File
    internal import Windows_Kernel_Process
    internal import WinSDK

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
            let actions = try _makeActions()
            let result = try _spawnWithActions(configuration, actions: actions)
            let handle = Process.Handle(processInfo: consume result)
            let status = try handle.wait()
            return Process.Output(status: status)
        }

        @usableFromInline
        internal static func _runWithStdoutPipe(
            _ configuration: Configuration
        ) throws(Process.Error) -> Process.Output {
            var actions = try _makeActions()
            let stdoutPipe = try _makePipe()

            try _wireChildHandle(stdoutPipe.write, into: &actions, slot: .stdout)

            let result = try _spawnWithActions(configuration, actions: actions)
            let stdoutRead = try _closeWriteEnd(stdoutPipe)
            let captured = try _drainBytes(stdoutRead)
            let handle = Process.Handle(processInfo: consume result)
            let status = try handle.wait()
            return Process.Output(status: status, stdout: captured, stderr: nil)
        }

        @usableFromInline
        internal static func _runWithStderrPipe(
            _ configuration: Configuration
        ) throws(Process.Error) -> Process.Output {
            var actions = try _makeActions()
            let stderrPipe = try _makePipe()

            try _wireChildHandle(stderrPipe.write, into: &actions, slot: .stderr)

            let result = try _spawnWithActions(configuration, actions: actions)
            let stderrRead = try _closeWriteEnd(stderrPipe)
            let captured = try _drainBytes(stderrRead)
            let handle = Process.Handle(processInfo: consume result)
            let status = try handle.wait()
            return Process.Output(status: status, stdout: nil, stderr: captured)
        }

        @usableFromInline
        internal static func _runWithBothPipes(
            _ configuration: Configuration
        ) throws(Process.Error) -> Process.Output {
            var actions = try _makeActions()
            let stdoutPipe = try _makePipe()
            let stderrPipe = try _makePipe()

            try _wireChildHandle(stdoutPipe.write, into: &actions, slot: .stdout)
            try _wireChildHandle(stderrPipe.write, into: &actions, slot: .stderr)

            let result = try _spawnWithActions(configuration, actions: actions)
            let stdoutRead = try _closeWriteEnd(stdoutPipe)
            let stderrRead = try _closeWriteEnd(stderrPipe)

            let capturedStdout = try _drainBytes(stdoutRead)
            let capturedStderr = try _drainBytes(stderrRead)

            let handle = Process.Handle(processInfo: consume result)
            let status = try handle.wait()
            return Process.Output(
                status: status,
                stdout: capturedStdout,
                stderr: capturedStderr
            )
        }
    }

    extension Process.Spawn {

        @usableFromInline
        internal enum _StdioSlot { case stdout, stderr }
    }

    extension Process.Spawn {
        @usableFromInline
        internal static func _makeActions() throws(Process.Error)
            -> Windows.`32`.Kernel.Process.Spawn.Actions
        {
            do throws(Process.Error.Kernel) {
                return try Windows.`32`.Kernel.Process.Spawn.Actions()
            } catch {
                switch error {
                case .create(let code), .wait(let code):
                    throw .spawn(_processErrorFromCode(code))

                case .platform(let err):
                    throw .spawn(_processErrorFromCode(err.code))
                }
            }
        }

        @usableFromInline
        internal static func _makePipe() throws(Process.Error)
            -> Windows.`32`.Kernel.Pipe.Descriptors
        {
            do throws(Windows.`32`.Kernel.Pipe.Error) {
                return try Windows.`32`.Kernel.Pipe.pipe()
            } catch {
                switch error {
                case .handle(let e):
                    throw .capture(.win32(UInt32(ERROR_INVALID_HANDLE)))

                case .platform(let e):
                    throw .capture(e.code)
                }
            }
        }

        @usableFromInline
        internal static func _wireChildHandle(
            _ descriptor: borrowing Windows.`32`.Kernel.Descriptor,
            into actions: inout Windows.`32`.Kernel.Process.Spawn.Actions,
            slot: _StdioSlot
        ) throws(Process.Error) {
            do throws(Process.Error.Kernel) {
                try actions.markHandleInheritable(descriptor)
                switch slot {
                case .stdout: actions.setStdout(descriptor)
                case .stderr: actions.setStderr(descriptor)
                }
            } catch {
                switch error {
                case .create(let code), .wait(let code):
                    throw .spawn(_processErrorFromCode(code))

                case .platform(let err):
                    throw .spawn(_processErrorFromCode(err.code))
                }
            }
        }

        @usableFromInline
        internal static func _spawnWithActions(
            _ configuration: Configuration,
            actions: borrowing Windows.`32`.Kernel.Process.Spawn.Actions
        ) throws(Process.Error) -> Windows.`32`.Kernel.Process.Spawn.Result {

            var commandLineString = _quoteWindowsCommandLineArgument(configuration.executable)
            for arg in configuration.arguments {
                commandLineString += " " + _quoteWindowsCommandLineArgument(arg)
            }
            var commandLineUnits: [WCHAR] = Array(commandLineString.utf16)
            commandLineUnits.append(0)

            let envBlock: [WCHAR]? = _flattenWideEnvironment(configuration.environment)

            let cwdUnits: [WCHAR]? = configuration.workingDirectory.map { dir in
                var units = Array(dir.utf16)
                units.append(0)
                return units
            }

            let resolvedExecutable = try Executable.resolve(configuration.executable)
            var executableUnits = Array(resolvedExecutable.utf16)
            executableUnits.append(0)

            var spawnedResult: Windows.`32`.Kernel.Process.Spawn.Result?

            do throws(Process.Error.Kernel) {

                try unsafe executableUnits.withUnsafeBufferPointer {
                    (
                        exePtr: UnsafeBufferPointer<WCHAR>
                    ) throws(Process.Error.Kernel)
                    in
                    try unsafe commandLineUnits.withUnsafeMutableBufferPointer {
                        (
                            cmdPtr: inout UnsafeMutableBufferPointer<WCHAR>
                        ) throws(Process.Error.Kernel) in
                        try _withOptionalWideBuffer(cwdUnits) {
                            (
                                cwdPtr: UnsafePointer<WCHAR>?
                            ) throws(Process.Error.Kernel) in
                            try _withOptionalWideBuffer(envBlock) {
                                (
                                    envPtr: UnsafePointer<WCHAR>?
                                ) throws(Process.Error.Kernel) in
                                spawnedResult = try unsafe Windows.`32`.Kernel.Process.Spawn.spawn(
                                    executable: exePtr.baseAddress,
                                    commandLine: cmdPtr.baseAddress!,
                                    environment: envPtr.map {
                                        unsafe UnsafeMutableRawPointer(mutating: $0)
                                    },
                                    workingDirectory: cwdPtr,
                                    actions: actions
                                )
                            }
                        }
                    }
                }
            } catch {
                switch error {
                case .create(let code), .wait(let code):
                    throw .spawn(_processErrorFromCode(code))

                case .platform(let err):
                    throw .spawn(_processErrorFromCode(err.code))
                }
            }

            guard let result = consume spawnedResult else {

                preconditionFailure(
                    "Windows.`32`.Kernel.Process.Spawn.spawn produced neither a result nor a thrown error"
                )
            }
            return result
        }

        internal static func _withOptionalWideBuffer<R>(
            _ array: [WCHAR]?,
            _ body: (UnsafePointer<WCHAR>?) throws(Process.Error.Kernel) -> R
        ) throws(Process.Error.Kernel) -> R {
            guard let array else {
                return try body(nil)
            }
            return try unsafe array.withUnsafeBufferPointer {
                (
                    buffer: UnsafeBufferPointer<WCHAR>
                ) throws(Process.Error.Kernel) -> R
                in
                try body(unsafe buffer.baseAddress)
            }
        }

        @usableFromInline
        internal static func _closeWriteEnd(
            _ pipe: consuming Windows.`32`.Kernel.Pipe.Descriptors
        ) throws(Process.Error) -> Windows.`32`.Kernel.Descriptor {

            let pair = consume pipe.underlying
            let read = pair.first

            _ = pair.second
            return read
        }

        @usableFromInline
        internal static func _drainBytes(
            _ descriptor: consuming Windows.`32`.Kernel.Descriptor
        ) throws(Process.Error) -> [UInt8] {
            var buffer: [UInt8] = []
            var chunk = [UInt8](repeating: 0, count: 4096)

            let handle = unsafe UnsafeMutableRawPointer(bitPattern: descriptor._rawValue)
            guard let handle else {
                throw .capture(.win32(UInt32(ERROR_INVALID_HANDLE)))
            }

            while true {
                var bytesRead: DWORD = 0
                let success = unsafe chunk.withUnsafeMutableBufferPointer { ptr in
                    ReadFile(
                        handle,
                        ptr.baseAddress,
                        DWORD(ptr.count),
                        &bytesRead,
                        nil
                    )
                }
                if !success {
                    let err = unsafe GetLastError()
                    if err == ERROR_BROKEN_PIPE {
                        break
                    }
                    throw .capture(.win32(err))
                }
                if bytesRead == 0 { break }
                buffer.append(contentsOf: chunk.prefix(Int(bytesRead)))
            }

            _ = consume descriptor
            return buffer
        }

        internal static func _flattenWideEnvironment(
            _ environment: [Swift.String: Swift.String]?
        ) -> [WCHAR]? {
            guard let environment else { return nil }
            var block: [WCHAR] = []
            for key in environment.keys.sorted() {
                let value = environment[key] ?? ""
                let entry = "\(key)=\(value)"
                block.append(contentsOf: entry.utf16)
                block.append(0)
            }
            block.append(0)
            return block
        }

        @usableFromInline
        internal static func _processErrorFromCode(
            _ code: Error::Error.Code
        ) -> Process.Error.Kernel {
            .create(code)
        }
    }

#endif

extension Process.Spawn {

    @usableFromInline
    internal static func _quoteWindowsCommandLineArgument(_ argument: Swift.String) -> Swift.String
    {
        let needsQuoting =
            argument.isEmpty
            || argument.contains(where: {
                $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\u{0B}" || $0 == "\""
            })
        guard needsQuoting else {
            return argument
        }

        var quoted: Swift.String = "\""
        var backslashRun = 0
        for character in argument {
            if character == "\\" {
                backslashRun += 1
                continue
            }
            if character == "\"" {

                quoted += Swift.String(repeating: "\\", count: backslashRun * 2 + 1)
                quoted += "\""
                backslashRun = 0
                continue
            }
            if backslashRun > 0 {

                quoted += Swift.String(repeating: "\\", count: backslashRun)
                backslashRun = 0
            }
            quoted.append(character)
        }

        quoted += Swift.String(repeating: "\\", count: backslashRun * 2)
        quoted += "\""
        return quoted
    }
}
