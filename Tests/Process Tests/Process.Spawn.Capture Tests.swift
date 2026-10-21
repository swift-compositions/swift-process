#if !os(Windows)

    import Testing
    @testable import Process

    extension Process.Spawn {
        @Suite("Process pipe capture + workingDirectory")
        struct Test {

            @Test("echo hello → captured stdout is 'hello\\n'")
            func `captureEchoStdout`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/echo",
                        arguments: ["hello"],
                        stdout: .pipe
                    )
                )
                #expect(output.status == .exited(code: 0))
                #expect(output.stderr == nil)

                let bytes = try #require(output.stdout)
                let text = Swift.String(decoding: bytes, as: UTF8.self)
                #expect(text == "hello\n")
            }

            @Test("sh -c 'echo err >&2' → captured stderr is 'err\\n'")
            func `captureStderrFromSubshell`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/sh",
                        arguments: ["-c", "echo err 1>&2"],
                        stderr: .pipe
                    )
                )
                #expect(output.status == .exited(code: 0))
                #expect(output.stdout == nil)

                let bytes = try #require(output.stderr)
                let text = Swift.String(decoding: bytes, as: UTF8.self)
                #expect(text == "err\n")
            }

            @Test
            func `sh -c '… stdout … stderr …' → both captured`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/sh",
                        arguments: ["-c", "echo out; echo err 1>&2"],
                        stdout: .pipe,
                        stderr: .pipe
                    )
                )
                #expect(output.status == .exited(code: 0))

                let outBytes = try #require(output.stdout)
                let errBytes = try #require(output.stderr)
                #expect(Swift.String(decoding: outBytes, as: UTF8.self) == "out\n")
                #expect(Swift.String(decoding: errBytes, as: UTF8.self) == "err\n")
            }

            @Test
            func `pwd with workingDirectory: '/tmp' → child cwd is /tmp`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/pwd",
                        stdout: .pipe,
                        workingDirectory: "/tmp"
                    )
                )
                #expect(output.status == .exited(code: 0))

                let bytes = try #require(output.stdout)
                let text = Swift.String(decoding: bytes, as: UTF8.self)
                    .trimmingTrailingNewlines

                #expect(text == "/tmp" || text == "/private/tmp", "got: \(text)")
            }

            @Test
            func `stdin: .pipe is rejected with streamPolicyUnsupported (v2)`() throws {
                do throws(Process.Error) {
                    _ = try Process.Spawn.run(
                        Process.Spawn.Configuration(
                            executable: "/usr/bin/cat",
                            stdin: .pipe,
                            stdout: .pipe
                        )
                    )
                    Issue.record("expected throw")
                } catch {
                    #expect(error == .streamPolicyUnsupported)
                }
            }

            @Test
            func `spawn() rejects .pipe streams (run() is the v2 entry point)`() throws {
                do throws(Process.Error) {
                    _ = try Process.Spawn.spawn(
                        Process.Spawn.Configuration(
                            executable: "/usr/bin/true",
                            stdout: .pipe
                        )
                    )
                    Issue.record("expected throw")
                } catch {
                    #expect(error == .streamPolicyUnsupported)
                }
            }

            @Test
            func `spawn() rejects non-nil workingDirectory`() throws {
                do throws(Process.Error) {
                    _ = try Process.Spawn.spawn(
                        Process.Spawn.Configuration(
                            executable: "/usr/bin/true",
                            workingDirectory: "/tmp"
                        )
                    )
                    Issue.record("expected throw")
                } catch {
                    #expect(error == .streamPolicyUnsupported)
                }
            }
        }
    }

    extension Swift.String {
        fileprivate var trimmingTrailingNewlines: Swift.String {
            var s = self
            while s.last == "\n" || s.last == "\r" {
                s.removeLast()
            }
            return s
        }
    }

#endif
