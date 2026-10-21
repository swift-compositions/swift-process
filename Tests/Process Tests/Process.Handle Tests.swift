#if os(Windows)

    import Testing
    @testable import Process

    extension Process.Handle {
        @Suite
        struct Unit {
            @Test(
                "wait() on a freshly spawned child returns its own exit code, not a stale/closed-HANDLE failure"
            )
            func `waitReturnsRealExitCodeAfterSpawn`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "C:\\Windows\\System32\\cmd.exe",
                        arguments: ["/C", "exit 7"]
                    )
                )
                #expect(output.status == .exited(code: 7))
            }

            @Test(
                "Several sequential spawn+wait cycles each observe their own exit code (no HANDLE-reuse corruption)"
            )
            func `sequentialSpawnsEachReturnTheirOwnExitCode`() throws {
                for code in 0..<8 {
                    let output = try Process.Spawn.run(
                        Process.Spawn.Configuration(
                            executable: "C:\\Windows\\System32\\cmd.exe",
                            arguments: ["/C", "exit \(code)"]
                        )
                    )
                    #expect(output.status == .exited(code: Int32(code)), "iteration \(code)")
                }
            }
        }
    }

#endif
