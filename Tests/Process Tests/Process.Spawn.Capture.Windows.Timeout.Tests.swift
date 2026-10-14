#if os(Windows)
    import Testing
    @testable import Process

    extension Process.Spawn.Test {
        @Suite
        struct Integration {
            enum Streams: CaseIterable, Sendable {
                case inherited
                case stdout
                case stderr
                case both

                var output: Process.Stream {
                    switch self {
                    case .inherited, .stderr: .inherit
                    case .stdout, .both: .pipe
                    }
                }

                var error: Process.Stream {
                    switch self {
                    case .inherited, .stdout: .inherit
                    case .stderr, .both: .pipe
                    }
                }
            }
        }
    }

    extension Process.Spawn.Test.Integration {
        @Test(.timeLimit(.minutes(1)), arguments: Streams.allCases)
        func `fifty milliseconds bounds every capture policy`(
            _ streams: Streams
        ) throws(Process.Error) {
            let start = ContinuousClock().now
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "ping -n 7 127.0.0.1 >nul"],
                    stdout: streams.output,
                    stderr: streams.error,
                    timeout: .milliseconds(50)
                )
            )
            #expect(output.status == .signaled(signal: 9))
            #expect(ContinuousClock().now - start < .seconds(3))
            #expect((output.stdout != nil) == (streams.output == .pipe))
            #expect((output.stderr != nil) == (streams.error == .pipe))
        }

        @Test(.timeLimit(.minutes(1)))
        func `fast exit preserves its code and cancels the deadline`() throws(Process
            .Error)
        {
            let start = ContinuousClock().now
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "echo fast & exit /b 17"],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: .seconds(20)
                )
            )
            #expect(output.status == .exited(code: 17))
            #expect(ContinuousClock().now - start < .seconds(5))
            #expect(Swift.String(decoding: output.stdout ?? [], as: UTF8.self).contains("fast"))
        }

        @Test(.timeLimit(.minutes(1)))
        func `partial output survives a timeout`() throws(Process
            .Error)
        {
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: [
                        "/D", "/C",
                        "echo before-out & echo before-err 1>&2 & ping -n 7 127.0.0.1 >nul",
                    ],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: .seconds(1)
                )
            )
            #expect(output.status == .signaled(signal: 9))
            #expect(
                Swift.String(decoding: output.stdout ?? [], as: UTF8.self).contains("before-out"))
            #expect(
                Swift.String(decoding: output.stderr ?? [], as: UTF8.self).contains("before-err"))
        }

        @Test(.timeLimit(.minutes(1)))
        func `deadline survives root exit until inherited pipes close`()
            throws(Process
            .Error)
        {
            let start = ContinuousClock().now
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: [
                        "/D", "/C",
                        "start /b ping.exe -n 7 127.0.0.1 & echo root-exited & exit /b 0",
                    ],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: .seconds(1)
                )
            )
            #expect(output.status == .signaled(signal: 9))
            #expect(ContinuousClock().now - start < .seconds(3))
            #expect(
                Swift.String(decoding: output.stdout ?? [], as: UTF8.self).contains("root-exited"))
        }

        @Test(.timeLimit(.minutes(1)))
        func `timeout preserves an unrelated process`() throws(Process.Error) {
            let bystander = try Process.Spawn.spawn(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "ping -n 3 127.0.0.1 >nul & exit /b 29"]
                )
            )
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "ping -n 7 127.0.0.1 >nul"],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: .milliseconds(50)
                )
            )
            let status = try bystander.wait()
            #expect(output.status == .signaled(signal: 9))
            #expect(status == .exited(code: 29))
        }

        @Test(.timeLimit(.minutes(1)), arguments: [Duration.zero, .milliseconds(-1)])
        func `nonpositive timeout never waits indefinitely`(
            _ timeout: Duration
        ) throws(Process.Error) {
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "ping -n 7 127.0.0.1 >nul"],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: timeout
                )
            )
            #expect(output.status == .signaled(signal: 9))
        }

        @Test(.timeLimit(.minutes(1)))
        func `nil timeout preserves normal completion`() throws(Process.Error) {
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "echo complete & exit /b 17"],
                    stdout: .pipe,
                    stderr: .pipe
                )
            )
            #expect(output.status == .exited(code: 17))
            #expect(Swift.String(decoding: output.stdout ?? [], as: UTF8.self).contains("complete"))
        }
    }
#endif
