#if os(Windows)
    import Testing
    import Synchronization
    import Windows_Kernel_Process
    import Windows_Kernel_Thread
    @testable import Process

    extension Process.Spawn.Test.Integration {
        final class Observation: Sendable {
            let result = Mutex<Result<Process.Status, Process.Error>?>(nil)
        }

        @Test(.timeLimit(.minutes(1)))
        func `reader creation failure cancels and waits the owned root`() throws(Process.Error) {
            let waited = Observation()
            var hooks = Process.Spawn.Capture.Hooks()
            hooks.launch = { _ throws(Windows.`32`.Kernel.Thread.Error) in
                throw .create(.init(code: .win32(8)))
            }
            hooks.waited = { result in waited.result.withLock { $0 = result } }
            let started = ContinuousClock().now
            do throws(Process.Error) {
                _ = try Process.Spawn.capture(
                    .init(
                        executable: #"C:\Windows\System32\cmd.exe"#,
                        arguments: ["/D", "/C", "ping -n 7 127.0.0.1 >nul"],
                        stdout: .pipe,
                        stderr: .pipe
                    ),
                    timeout: .seconds(20),
                    hooks: hooks
                )
                Issue.record("Expected the controlled reader creation failure")
            } catch {
                #expect(error == .capture(.win32(8)))
            }
            #expect(ContinuousClock().now - started < .seconds(3))
            if case .success = waited.result.withLock({ $0 }) {
            } else {
                Issue.record("The owned root was not waited after reader creation failed")
            }
        }

        @Test(.timeLimit(.minutes(1)))
        func `failed stdout cancels before joining the live stderr reader`() throws(Process.Error) {
            let ready = try Process.Spawn.Deadline.Test.Gate()
            let waited = Observation()
            var hooks = Process.Spawn.Capture.Hooks()
            hooks.read = { raw, stream in
                switch stream {
                case .stdout:
                    ready.wait()
                    return .failure(.capture(.win32(6)))
                case .stderr:
                    ready.release()
                    return Process.Spawn._drainRawHandle(raw)
                }
            }
            hooks.waited = { result in waited.result.withLock { $0 = result } }
            let started = ContinuousClock().now
            do throws(Process.Error) {
                _ = try Process.Spawn.capture(
                    .init(
                        executable: #"C:\Windows\System32\cmd.exe"#,
                        arguments: ["/D", "/C", "ping -n 7 127.0.0.1 >nul"],
                        stdout: .pipe,
                        stderr: .pipe
                    ),
                    timeout: .seconds(20),
                    hooks: hooks
                )
                Issue.record("Expected the controlled stdout failure")
            } catch {
                #expect(error == .capture(.win32(6)))
            }
            #expect(ContinuousClock().now - started < .seconds(3))
            if case .success = waited.result.withLock({ $0 }) {
            } else {
                Issue.record("The owned root was not waited after stdout failed")
            }
        }

        @Test(.timeLimit(.minutes(1)), arguments: [Streams.stdout, .stderr])
        func `single pipe failure waits the owned root`(_ stream: Streams) throws(Process.Error) {
            let waited = Observation()
            var hooks = Process.Spawn.Capture.Hooks()
            hooks.read = { _, _ in .failure(.capture(.win32(6))) }
            hooks.waited = { result in waited.result.withLock { $0 = result } }
            let started = ContinuousClock().now
            do throws(Process.Error) {
                _ = try Process.Spawn.capture(
                    .init(
                        executable: #"C:\Windows\System32\cmd.exe"#,
                        arguments: ["/D", "/C", "ping -n 7 127.0.0.1 >nul"],
                        stdout: stream.output,
                        stderr: stream.error
                    ),
                    timeout: .seconds(20),
                    hooks: hooks
                )
                Issue.record("Expected the controlled pipe failure")
            } catch {
                #expect(error == .capture(.win32(6)))
            }
            #expect(ContinuousClock().now - started < .seconds(3))
            if case .success = waited.result.withLock({ $0 }) {
            } else {
                Issue.record("The owned root was not waited after the pipe failed")
            }
        }

        @Test(.timeLimit(.minutes(1)))
        func `termination failure closes the owned job and releases both readers`() throws(Process
            .Error)
        {
            let waited = Observation()
            var hooks = Process.Spawn.Capture.Hooks()
            hooks.termination = { _ throws(Process.Error.Kernel) in throw .wait(.win32(5)) }
            hooks.waited = { result in waited.result.withLock { $0 = result } }
            let started = ContinuousClock().now
            do throws(Process.Error) {
                _ = try Process.Spawn.capture(
                    .init(
                        executable: #"C:\Windows\System32\cmd.exe"#,
                        arguments: ["/D", "/C", "ping -n 7 127.0.0.1 >nul"],
                        stdout: .pipe,
                        stderr: .pipe
                    ),
                    timeout: .milliseconds(50),
                    hooks: hooks
                )
                Issue.record("Expected the controlled job termination failure")
            } catch {
                #expect(error == .capture(.win32(5)))
            }
            #expect(ContinuousClock().now - started < .seconds(3))
            if case .success = waited.result.withLock({ $0 }) {
            } else {
                Issue.record("The owned root was not waited after job closure")
            }
        }
    }
#endif
