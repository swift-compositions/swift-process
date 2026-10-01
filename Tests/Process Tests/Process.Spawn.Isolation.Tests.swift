#if !os(Windows)

    import POSIX_Kernel
    import Testing
    @testable import Process

    extension Process.Spawn {
        @Suite
        struct `Isolation Tests` {

            @Test
            func `an inheritable descriptor held by the parent does not reach the child while stdio stays captured`() throws {
                let sentinel = try POSIX.Kernel.Pipe.pipe()
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/sh",
                        arguments: ["-c", "ls /dev/fd; echo done 1>&2"],
                        stdout: .pipe,
                        stderr: .pipe
                    )
                )
                _ = consume sentinel
                #expect(output.status == .exited(code: 0))

                let listing = Swift.String(decoding: try #require(output.stdout), as: UTF8.self)
                let descriptors = listing.split(separator: "\n").compactMap { Int($0) }
                #expect(descriptors.contains(0))
                #expect(descriptors.contains(1))
                #expect(descriptors.contains(2))
                #expect(descriptors.allSatisfy { $0 <= 3 })

                let diagnostics = Swift.String(decoding: try #require(output.stderr), as: UTF8.self)
                #expect(diagnostics == "done\n")
            }
        }
    }

#endif
