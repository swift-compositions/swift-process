#if !os(Windows)

    #if canImport(Darwin)
        import Darwin
    #elseif canImport(Glibc)
        import Glibc
    #endif
    @_spi(Syscall) import ISO_9945_Core
    import POSIX_Kernel
    import Testing
    @testable import Process

    extension Process.Spawn {
        @Suite
        struct `Isolation Tests` {

            static func identity(of descriptor: Int32) -> Swift.String? {
                var status = stat()
                guard fstat(descriptor, &status) == 0 else { return nil }
                return "\(status.st_dev):\(status.st_ino)"
            }

            static func probe(_ descriptor: Int32) -> [Swift.String] {
                ["-L", "-f", "%d:%i", "/dev/fd/\(descriptor)"]
            }

            @Test
            func `the sentinel is visible to a plain posix_spawn child, proving the probe sees inherited descriptors`() throws {
                let sentinel = try POSIX.Kernel.Pipe.pipe()
                let descriptor = sentinel.read._rawValue
                let expected = try #require(Self.identity(of: descriptor))

                let directory = "/tmp/process-isolation-control-\(getpid())-\(descriptor)"
                let path = directory + ".out"
                var actions: posix_spawn_file_actions_t? = nil
                #expect(posix_spawn_file_actions_init(&actions) == 0)
                defer { posix_spawn_file_actions_destroy(&actions) }
                #expect(posix_spawn_file_actions_addopen(&actions, 1, path, O_WRONLY | O_CREAT | O_TRUNC, 0o600) == 0)

                let arguments = ["/usr/bin/stat"] + Self.probe(descriptor)
                var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
                defer { argv.forEach { free($0) } }
                var pid: pid_t = 0
                #expect(posix_spawn(&pid, "/usr/bin/stat", &actions, nil, &argv, environ) == 0)
                var status: Int32 = 0
                #expect(waitpid(pid, &status, 0) == pid)
                defer { unlink(path) }

                let reported = try Swift.String(decoding: #require(FileContents.read(path)), as: UTF8.self)
                #expect(reported == expected + "\n", "control child reported \(reported) for descriptor \(descriptor), expected \(expected)")
                _ = consume sentinel
            }

            @Test
            func `the same sentinel is absent from an isolated Process.Spawn child while stdio stays captured`() throws {
                let sentinel = try POSIX.Kernel.Pipe.pipe()
                let descriptor = sentinel.read._rawValue
                _ = try #require(Self.identity(of: descriptor))

                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/usr/bin/stat",
                        arguments: Self.probe(descriptor),
                        stdout: .pipe,
                        stderr: .pipe
                    )
                )
                _ = consume sentinel

                let stdout = Swift.String(decoding: try #require(output.stdout), as: UTF8.self)
                let stderr = Swift.String(decoding: try #require(output.stderr), as: UTF8.self)
                #expect(output.status == .exited(code: 1), "stat must fail for the isolated sentinel; stdout=\(stdout) stderr=\(stderr)")
                #expect(stdout.isEmpty, "the isolated child saw the sentinel identity \(stdout)")
                #expect(stderr.contains("/dev/fd/\(descriptor)") && stderr.contains("Bad file descriptor"), "unexpected probe diagnostics: \(stderr)")
            }
        }
    }

    enum FileContents {
        static func read(_ path: Swift.String) -> [UInt8]? {
            guard let file = fopen(path, "r") else { return nil }
            defer { fclose(file) }
            var bytes: [UInt8] = []
            var buffer = [UInt8](repeating: 0, count: 256)
            while true {
                let count = fread(&buffer, 1, buffer.count, file)
                if count == 0 { break }
                bytes += buffer[0..<count]
            }
            return bytes
        }
    }

#endif
