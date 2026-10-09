#if os(Windows)

    import Testing
    @testable import Process

    extension Process.Spawn.Test {

        @Test
        func `stderr larger than the pipe buffer before any stdout completes with both streams`() throws {
            let line = "stderr-line-padding-0123456789-0123456789-0123456789"
            let output = try Process.Spawn.run(
                Process.Spawn.Configuration(
                    executable: "C:\\Windows\\System32\\cmd.exe",
                    arguments: ["/C", "(for /L %i in (1,1,2000) do @echo \(line) 1>&2) & echo done"],
                    stdout: .pipe,
                    stderr: .pipe
                )
            )
            #expect(output.status == .exited(code: 0))

            let stdout = Swift.String(decoding: try #require(output.stdout), as: UTF8.self)
            #expect(stdout == "done\r\n")

            let stderr = Swift.String(decoding: try #require(output.stderr), as: UTF8.self)
            let lines = stderr.split(separator: "\r\n")
            #expect(stderr.utf8.count > 65_536)
            #expect(lines.count == 2000)
            #expect(lines.allSatisfy { $0.hasPrefix(line) })
        }
    }

#endif
