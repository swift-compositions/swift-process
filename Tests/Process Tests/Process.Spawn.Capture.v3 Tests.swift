#if !os(Windows)

    import Testing
    @testable import Process

    extension Process.Spawn.Test {
        @Suite("Process v3: concurrent drain + timeout")
        struct V3 {

            @Test(.timeLimit(.minutes(1)))
            func `256 KiB stderr does not deadlock (v2 would hang)`() throws {

                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/sh",
                        arguments: [
                            "-c",
                            "dd if=/dev/zero bs=1024 count=256 1>&2 2>/dev/null; echo done",
                        ],
                        stdout: .pipe,
                        stderr: .pipe
                    )
                )
                #expect(output.status == .exited(code: 0))
                let stdoutBytes = try #require(output.stdout)
                let stderrBytes = try #require(output.stderr)

                let stdoutText = Swift.String(decoding: stdoutBytes, as: UTF8.self)
                #expect(stdoutText.contains("done"))

                #expect(
                    stderrBytes.count == 256 * 1024,
                    "expected exactly 256 KiB on stderr, got \(stderrBytes.count)"
                )
            }

            @Test(.timeLimit(.minutes(1)))
            func `256 KiB stdout does not deadlock`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/sh",
                        arguments: [
                            "-c",
                            "dd if=/dev/zero bs=1024 count=256 2>/dev/null; echo err 1>&2",
                        ],
                        stdout: .pipe,
                        stderr: .pipe
                    )
                )
                #expect(output.status == .exited(code: 0))
                let stdoutBytes = try #require(output.stdout)
                let stderrBytes = try #require(output.stderr)
                #expect(
                    stdoutBytes.count >= 256 * 1024,
                    "expected ≥ 256 KiB on stdout, got \(stdoutBytes.count)"
                )
                #expect(Swift.String(decoding: stderrBytes, as: UTF8.self) == "err\n")
            }

            @Test(.timeLimit(.minutes(1)))
            func `128 KiB on both pipes does not deadlock`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/sh",
                        arguments: [
                            "-c",
                            """
                            dd if=/dev/zero bs=1024 count=128 2>/dev/null; \
                            dd if=/dev/zero bs=1024 count=128 1>&2 2>/dev/null
                            """,
                        ],
                        stdout: .pipe,
                        stderr: .pipe
                    )
                )
                #expect(output.status == .exited(code: 0))
                let stdoutBytes = try #require(output.stdout)
                let stderrBytes = try #require(output.stderr)
                #expect(
                    stdoutBytes.count == 128 * 1024,
                    "expected exactly 128 KiB on stdout, got \(stdoutBytes.count)"
                )
                #expect(
                    stderrBytes.count == 128 * 1024,
                    "expected exactly 128 KiB on stderr, got \(stderrBytes.count)"
                )
            }

            @Test(
                .timeLimit(.minutes(1))
            )
            func `timeout fires: sleep 30 with 1s timeout → .signaled(SIGKILL)`() throws {
                let started = ContinuousClock().now
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/sleep",
                        arguments: ["30"],
                        timeout: .seconds(1)
                    )
                )
                let elapsed = ContinuousClock().now - started

                guard case .signaled(let signal) = output.status else {
                    Issue.record("expected .signaled, got \(output.status)")
                    return
                }
                #expect(signal == 9, "expected SIGKILL (9), got \(signal)")

                #expect(elapsed < .seconds(5), "elapsed: \(elapsed)")
            }

            @Test(
                .timeLimit(.minutes(1))
            )
            func `timeout does not fire when child is fast`() throws {
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/echo",
                        arguments: ["hello"],
                        timeout: .seconds(10)
                    )
                )
                #expect(output.status == .exited(code: 0))
            }

            @Test(
                .timeLimit(.minutes(1))
            )
            func `timeout fires while pipes are armed`() throws {
                let started = ContinuousClock().now
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/bin/sleep",
                        arguments: ["30"],
                        stdout: .pipe,
                        stderr: .pipe,
                        timeout: .seconds(1)
                    )
                )
                let elapsed = ContinuousClock().now - started

                guard case .signaled(let signal) = output.status else {
                    Issue.record("expected .signaled, got \(output.status)")
                    return
                }
                #expect(signal == 9)
                #expect(elapsed < .seconds(5))

                #expect(output.stdout != nil)
                #expect(output.stderr != nil)
            }

            @Test(
                .timeLimit(.minutes(1))
            )
            func `partial capture survives the timeout kill`() throws {
                let started = ContinuousClock().now
                let output = try Process.Spawn.run(
                    Process.Spawn.Configuration(
                        executable: "/usr/bin/yes",
                        arguments: ["HELLO_BEFORE_KILL"],
                        stdout: .pipe,
                        stderr: .pipe,
                        timeout: .seconds(1)
                    )
                )
                let elapsed = ContinuousClock().now - started

                guard case .signaled(let signal) = output.status else {
                    Issue.record("expected .signaled, got \(output.status)")
                    return
                }
                #expect(signal == 9)

                #expect(elapsed < .seconds(5), "elapsed: \(elapsed)")

                let bytes = try #require(output.stdout)
                let text = Swift.String(decoding: bytes, as: UTF8.self)
                #expect(
                    text.contains("HELLO_BEFORE_KILL"),
                    "captured stdout (first 200 chars): \(text.prefix(200))"
                )
                #expect(bytes.count > 0, "expected non-empty capture")
            }

            @Test
            func `nil timeout preserves indefinite-wait behavior`() throws {
                let configuration = Process.Spawn.Configuration(
                    executable: "/usr/bin/true"
                )
                #expect(configuration.timeout == nil)
                let output = try Process.Spawn.run(configuration)
                #expect(output.status == .exited(code: 0))
            }
        }
    }

#endif
