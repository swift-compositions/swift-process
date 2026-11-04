#if os(Windows)

    import Testing
    @testable import Process

    extension Process.Handle {
        @Suite
        struct Unit {
            @Test
            func `wait() on a freshly spawned child returns its own exit code, not a stale/closed-HANDLE failure`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "C:\\Windows\\System32\\cmd.exe",
                        arguments: ["/C", "exit 7"]
                    )
                )
                #expect(output.status == .exited(code: 7))
            }

            @Test
            func `Several sequential spawn+wait cycles each observe their own exit code (no HANDLE-reuse corruption)`() throws {
                for code in Array(0..<8) {
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
