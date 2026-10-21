#if os(Windows)

    import Testing
    @testable import Process

    extension Process.Spawn {
        @Suite
        struct Integration {
            @Test(
                "Spawn with simultaneous workingDirectory + environment: both the child's cwd and its environment reflect the values passed, not garbage from a dangling pointer"
            )
            func `spawnWithWorkingDirectoryAndEnvironmentBothTakeEffect`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "C:\\Windows\\System32\\cmd.exe",
                        arguments: ["/C", "echo %CD% & set REGRESSION_MARKER"],
                        environment: [
                            "SystemRoot": "C:\\Windows",
                            "REGRESSION_MARKER": "f-003-marker",
                        ],
                        stdout: .pipe,
                        workingDirectory: "C:\\Windows\\System32"
                    )
                )
                #expect(output.status == .exited(code: 0))

                let bytes = try #require(output.stdout)
                let text = Swift.String(decoding: bytes, as: UTF8.self)
                #expect(
                    text.lowercased().contains("system32"),
                    "workingDirectory not observed by child, got: \(text)"
                )
                #expect(
                    text.contains("REGRESSION_MARKER=f-003-marker"),
                    "environment not observed by child, got: \(text)"
                )
            }
        }
    }

#endif
