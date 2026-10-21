#if !os(Windows)

    import Testing
    @testable import Process

    extension Process.Spawn.Test {
        @Test
        func `Spawning /usr/bin/true returns exit code 0`() throws {
            let output = try Process.Spawn.run(
                Process.Spawn.Configuration(executable: "/usr/bin/true")
            )
            #expect(output.status == .exited(code: 0))
            #expect(output.stdout == nil)
            #expect(output.stderr == nil)
        }

        @Test
        func `Spawning /usr/bin/false returns exit code 1`() throws {
            let output = try Process.Spawn.run(
                Process.Spawn.Configuration(executable: "/usr/bin/false")
            )
            #expect(output.status == .exited(code: 1))
        }

        @Test
        func `Spawning /usr/bin/env with explicit environment yields exit 0`() throws {
            let output = try Process.Spawn.run(
                Process.Spawn.Configuration(
                    executable: "/usr/bin/env",
                    arguments: ["true"],
                    environment: ["PATH": "/usr/bin:/bin"]
                )
            )
            #expect(output.status == .exited(code: 0))
        }

        @Test
        func `Interior NUL in executable path is rejected at index 0`() throws {
            do throws(Process.Error) {
                _ = try Process.Spawn.run(
                    Process.Spawn.Configuration(executable: "/usr/bin/\0true")
                )
                Issue.record("expected throw, got success")
            } catch {
                #expect(error == .invalidPath(index: 0))
            }
        }

        @Test
        func `Spawning a non-existent executable surfaces a typed spawn error`() throws {
            do throws(Process.Error) {
                _ = try Process.Spawn.run(
                    Process.Spawn.Configuration(executable: "/nonexistent/path/binary")
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

#endif
