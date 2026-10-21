#if os(Windows)

    import Testing
    @testable import Process

    extension Process.Spawn.Test {
        @Suite("Process spawn smoke tests (Windows)")
        struct Windows {
            @Test
            func `Spawning cmd.exe /C 'exit 0' returns exit code 0`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "C:\\Windows\\System32\\cmd.exe",
                        arguments: ["/C", "exit 0"]
                    )
                )
                #expect(output.status == .exited(code: 0))
                #expect(output.stdout == nil)
                #expect(output.stderr == nil)
            }

            @Test
            func `Spawning cmd.exe /C 'exit 1' returns exit code 1`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "C:\\Windows\\System32\\cmd.exe",
                        arguments: ["/C", "exit 1"]
                    )
                )
                #expect(output.status == .exited(code: 1))
            }

            @Test
            func `Spawning cmd.exe with explicit environment yields exit 0`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "C:\\Windows\\System32\\cmd.exe",
                        arguments: ["/C", "exit 0"],
                        environment: ["SystemRoot": "C:\\Windows"]
                    )
                )
                #expect(output.status == .exited(code: 0))
            }

            @Test
            func `Spawning a non-existent executable surfaces a typed spawn error`() throws {
                do throws(Process.Error) {
                    _ = try Process.Spawn.run(
                        Process.Spawn.Configuration(
                            executable: "C:\\nonexistent\\path\\binary.exe"
                        )
                    )
                    Issue.record("expected throw, got success")
                } catch {

                    switch error {
                    case .spawn: break
                    default: Issue.record("unexpected error: \(error)")
                    }
                }
            }
        }
    }

#endif
