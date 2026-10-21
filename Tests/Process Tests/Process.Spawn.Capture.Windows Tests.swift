#if os(Windows)

    import Testing
    @testable import Process

    extension Process.Spawn {
        @Suite("Process pipe capture + workingDirectory (Windows)")
        struct Test {

            @Test("cmd.exe /C 'echo hello' → captured stdout is 'hello\\r\\n'")
            func `captureEchoStdout`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "C:\\Windows\\System32\\cmd.exe",
                        arguments: ["/C", "echo hello"],
                        stdout: .pipe
                    )
                )
                #expect(output.status == .exited(code: 0))
                #expect(output.stderr == nil)

                let bytes = try #require(output.stdout)
                let text = Swift.String(decoding: bytes, as: UTF8.self)
                #expect(text == "hello\r\n")
            }

            @Test("cmd.exe /C 'echo err 1>&2' → captured stderr is 'err \\r\\n'")
            func `captureStderrFromCmd`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "C:\\Windows\\System32\\cmd.exe",
                        arguments: ["/C", "echo err 1>&2"],
                        stderr: .pipe
                    )
                )
                #expect(output.status == .exited(code: 0))
                #expect(output.stdout == nil)

                let bytes = try #require(output.stderr)
                let text = Swift.String(decoding: bytes, as: UTF8.self)

                #expect(text == "err \r\n")
            }

            @Test(
                .disabled(
                    """
                    Blocked on swift-microsoft/swift-windows-32#18: `Spawn.Actions` sizes its \
                    `PROC_THREAD_ATTRIBUTE_LIST` for a single attribute entry but issues one \
                    `UpdateProcThreadAttribute` per handle, so wiring a second inheritable handle \
                    fails with `ERROR_GEN_FAILURE` (31). This is the suite's only both-pipes \
                    configuration and therefore the only test the defect reaches; every \
                    single-pipe capture test spawns and captures correctly. Tracked here as \
                    swift-compositions/swift-process#6 — re-enable once the owning fix lands \
                    upstream.
                    """
                )
            )
            func `powershell.exe Write-Output 'out' + Write-Error 'err' → both captured`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable:
                            "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
                        arguments: [
                            "-NoProfile",
                            "-Command",
                            "Write-Output 'out'; Write-Error 'err'",
                        ],
                        stdout: .pipe,
                        stderr: .pipe
                    )
                )

                let outBytes = try #require(output.stdout)
                let errBytes = try #require(output.stderr)
                let outText = Swift.String(decoding: outBytes, as: UTF8.self)
                let errText = Swift.String(decoding: errBytes, as: UTF8.self)
                #expect(outText.contains("out"))
                #expect(errText.contains("err"))
            }

            @Test(
                "cmd.exe /C 'echo %CD%' with workingDirectory: 'C:\\Windows' → cwd is C:\\Windows"
            )
            func `workingDirectoryCD`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "C:\\Windows\\System32\\cmd.exe",
                        arguments: ["/C", "echo %CD%"],
                        stdout: .pipe,
                        workingDirectory: "C:\\Windows"
                    )
                )
                #expect(output.status == .exited(code: 0))

                let bytes = try #require(output.stdout)
                let text = Swift.String(decoding: bytes, as: UTF8.self)
                    .trimmingTrailingNewlinesWin

                #expect(text.lowercased() == "c:\\windows", "got: \(text)")
            }

            @Test
            func `stdin: .pipe is rejected with streamPolicyUnsupported (v2)`() throws {
                do throws(Process.Error) {
                    _ = try Process.Spawn.run(
                        Process.Spawn.Configuration(
                            executable: "C:\\Windows\\System32\\cmd.exe",
                            arguments: ["/C", "type CON"],
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
                            executable: "C:\\Windows\\System32\\cmd.exe",
                            arguments: ["/C", "exit 0"],
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
                            executable: "C:\\Windows\\System32\\cmd.exe",
                            arguments: ["/C", "exit 0"],
                            workingDirectory: "C:\\Windows"
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

        fileprivate var trimmingTrailingNewlinesWin: Swift.String {
            var s = self
            while let last = s.last, last.isNewline {
                s.removeLast()
            }
            return s
        }
    }

#endif
