#if canImport(Darwin)

    import Darwin
    @_spi(Syscall) import ISO_9945_Core
    @_spi(Syscall) import ISO_9945_Kernel_Process
    import POSIX_Kernel
    import Testing
    @testable import Process

    enum IsolationFixture {

        struct Failure: Swift.Error, CustomStringConvertible {
            let description: Swift.String
        }

        struct Exit: Equatable, CustomStringConvertible {
            let normal: Bool
            let code: Int32
            var description: Swift.String { normal ? "exited(\(code))" : "signalled(\(code))" }
        }

        enum Stdio {
            case redirected
            case closedStdin
            case inherited
        }

        static func identity(of descriptor: Int32) throws -> Swift.String {
            var status = stat()
            guard fstat(descriptor, &status) == 0 else {
                throw Failure(description: "fstat(\(descriptor)) failed, errno \(errno)")
            }
            return "\(status.st_ino)"
        }

        static func uniqueOutput() throws -> Swift.String {
            var template = Array("/tmp/process-isolation-XXXXXX".utf8CString)
            let descriptor = template.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
            guard descriptor >= 0 else { throw Failure(description: "mkstemp failed, errno \(errno)") }
            let path = template.withUnsafeBufferPointer { Swift.String(cString: $0.baseAddress!) }
            guard close(descriptor) == 0 else {
                let error = errno
                unlink(path)
                throw Failure(description: "close(\(descriptor)) failed, errno \(error)")
            }
            return path
        }

        static func read(_ path: Swift.String) throws -> Swift.String {
            guard let file = fopen(path, "r") else { throw Failure(description: "cannot open \(path), errno \(errno)") }
            defer { fclose(file) }
            var bytes: [UInt8] = []
            var buffer = [UInt8](repeating: 0, count: 256)
            while true {
                let count = fread(&buffer, 1, buffer.count, file)
                if count == 0 { break }
                bytes += buffer[0..<count]
            }
            return Swift.String(decoding: bytes, as: UTF8.self)
        }

        static func probe(_ descriptors: Int32...) -> [Swift.String] {
            ["/usr/bin/stat", "-L", "-f", "%i"] + descriptors.map { "/dev/fd/\($0)" }
        }

        static func spawn(
            _ arguments: [Swift.String],
            output: Swift.String,
            stdio: Stdio,
            isolated: Bool
        ) throws -> Exit {
            var actions = try ISO_9945.Kernel.Process.Spawn.Actions()
            if isolated {
                guard try actions.isolate() else { throw Failure(description: "descriptor isolation is unsupported here") }
            }
            switch stdio {
            case .inherited:
                break
            case .redirected, .closedStdin:
                let path = Array(output.utf8) + [0]
                for target in [ISO_9945.Kernel.Process.Spawn.Actions.Target.stdout, .stderr] {
                    try path.withUnsafeBufferPointer { buffer in
                        try unsafe actions.add(open: target, path: buffer.baseAddress!, flags: O_WRONLY | O_APPEND, mode: 0)
                    }
                }
                if case .closedStdin = stdio { try actions.add(close: .stdin) }
            }

            let vector = arguments.map { strdup($0) }
            defer { vector.forEach { free($0) } }
            guard vector.allSatisfy({ $0 != nil }) else { throw Failure(description: "strdup failed") }
            let argv: [UnsafePointer<CChar>?] = vector.map { UnsafePointer($0) } + [nil]
            let envp = UnsafeRawPointer(environ).assumingMemoryBound(to: UnsafePointer<CChar>?.self)

            let pid = try argv.withUnsafeBufferPointer { buffer in
                try unsafe ISO_9945.Kernel.Process.Spawn.spawn(
                    path: buffer[0]!,
                    argv: buffer.baseAddress!,
                    envp: envp,
                    actions: actions,
                    isolated: isolated
                )
            }.rawValue
            guard pid > 0 else { throw Failure(description: "spawn reported success with pid \(pid)") }

            var status: Int32 = 0
            var reaped: pid_t
            repeat { reaped = waitpid(pid, &status, 0) } while reaped == -1 && errno == EINTR
            guard reaped == pid else { throw Failure(description: "waitpid(\(pid)) returned \(reaped), errno \(errno)") }
            return (status & 0x7f) == 0 ? Exit(normal: true, code: (status >> 8) & 0xff) : Exit(normal: false, code: status & 0x7f)
        }
    }

    extension Process.Spawn {
        @Suite
        struct `Isolation Tests` {

            @Test
            func `one retained sentinel reaches an unisolated low-level child and not an isolated one with redirected stdio`() throws {
                let control = try IsolationFixture.uniqueOutput()
                defer { unlink(control) }
                let isolated = try IsolationFixture.uniqueOutput()
                defer { unlink(isolated) }
                let sentinelPath = try IsolationFixture.uniqueOutput()
                defer { unlink(sentinelPath) }
                let descriptor = open(sentinelPath, O_RDONLY)
                guard descriptor >= 0 else { throw IsolationFixture.Failure(description: "open(\(sentinelPath)) failed, errno \(errno)") }
                defer { close(descriptor) }
                let expected = try IsolationFixture.identity(of: descriptor)

                let controlExit = try IsolationFixture.spawn(
                    IsolationFixture.probe(descriptor), output: control, stdio: .redirected, isolated: false
                )
                let isolatedExit = try IsolationFixture.spawn(
                    IsolationFixture.probe(descriptor), output: isolated, stdio: .redirected, isolated: true
                )
                let retained = try IsolationFixture.identity(of: descriptor)
                let controlReport = try IsolationFixture.read(control)
                let isolatedReport = try IsolationFixture.read(isolated)

                #expect(retained == expected, "the sentinel changed identity between spawns: \(expected) then \(retained)")
                #expect(controlExit == .init(normal: true, code: 0), "control child \(controlExit): \(controlReport)")
                #expect(controlReport == expected + "\n", "control child reported \(controlReport) for fd \(descriptor), expected \(expected)")
                #expect(isolatedExit == .init(normal: true, code: 1), "isolated child \(isolatedExit): \(isolatedReport)")
                #expect(isolatedReport.contains("/dev/fd/\(descriptor)") && isolatedReport.contains("Bad file descriptor"), "unexpected probe output: \(isolatedReport)")
            }

            @Test
            func `an isolated low-level spawn keeps a closed stdin closed`() throws {
                let output = try IsolationFixture.uniqueOutput()
                defer { unlink(output) }

                let exit = try IsolationFixture.spawn(
                    IsolationFixture.probe(0), output: output, stdio: .closedStdin, isolated: true
                )
                let reported = try IsolationFixture.read(output)

                #expect(exit == .init(normal: true, code: 1), "closed-stdin child \(exit): \(reported)")
                #expect(reported.contains("/dev/fd/0") && reported.contains("Bad file descriptor"), "unexpected probe output: \(reported)")
            }

            @Test
            func `an isolated low-level spawn inherits the same stdio as an unisolated one`() throws {
                let control = try IsolationFixture.uniqueOutput()
                defer { unlink(control) }
                let isolated = try IsolationFixture.uniqueOutput()
                defer { unlink(isolated) }

                let probe: (Swift.String) -> [Swift.String] = { output in
                    ["/bin/sh", "-c", "exec 7<&0 8>&1 9>&2; exec /usr/bin/stat -L -f %d:%i /dev/fd/7 /dev/fd/8 /dev/fd/9 > '\(output)' 2>&1"]
                }
                let controlExit = try IsolationFixture.spawn(probe(control), output: control, stdio: .inherited, isolated: false)
                let isolatedExit = try IsolationFixture.spawn(probe(isolated), output: isolated, stdio: .inherited, isolated: true)
                let controlReport = try IsolationFixture.read(control)
                let isolatedReport = try IsolationFixture.read(isolated)

                #expect(controlExit == .init(normal: true, code: 0), "unisolated child \(controlExit): \(controlReport)")
                #expect(isolatedExit == .init(normal: true, code: 0), "isolated child \(isolatedExit): \(isolatedReport)")
                #expect(controlReport.split(separator: "\n").count == 3, "unisolated child saw \(controlReport)")
                #expect(isolatedReport == controlReport, "isolated stdio \(isolatedReport), unisolated stdio \(controlReport)")
            }

            @Test
            func `a Process.Spawn child does not see the retained sentinel while stdio stays captured`() throws {
                let sentinel = try POSIX.Kernel.Pipe.pipe()
                let descriptor = sentinel.read._rawValue
                _ = try IsolationFixture.identity(of: descriptor)

                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/usr/bin/stat",
                        arguments: Array(IsolationFixture.probe(descriptor).dropFirst()),
                        stdout: .pipe,
                        stderr: .pipe
                    )
                )
                _ = consume sentinel

                let stdout = Swift.String(decoding: try #require(output.stdout), as: UTF8.self)
                let stderr = Swift.String(decoding: try #require(output.stderr), as: UTF8.self)
                #expect(output.status == .exited(code: 1), "stdout=\(stdout) stderr=\(stderr)")
                #expect(stdout.isEmpty, "the isolated child saw the sentinel identity \(stdout)")
                #expect(stderr.contains("/dev/fd/\(descriptor)") && stderr.contains("Bad file descriptor"), "unexpected probe diagnostics: \(stderr)")
            }
        }
    }

#endif
