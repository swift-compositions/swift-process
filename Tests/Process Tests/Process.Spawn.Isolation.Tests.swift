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
                let probe = "for fd in $(seq 3 255); do if { true >&$fd; } 2>/dev/null; then echo $fd; fi; done; echo done 1>&2"
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/sh",
                        arguments: ["-c", probe],
                        stdout: .pipe,
                        stderr: .pipe
                    )
                )
                _ = consume sentinel
                #expect(output.status == .exited(code: 0))

                let listing = Swift.String(decoding: try #require(output.stdout), as: UTF8.self)
                let inherited = listing.split(separator: "\n").compactMap { Int($0) }
                #expect(inherited.isEmpty, "descriptors above 2 reached the child: \(inherited)")

                let diagnostics = Swift.String(decoding: try #require(output.stderr), as: UTF8.self)
                #expect(diagnostics == "done\n")
            }
        }
    }

#endif
