#if os(Windows)
    import Testing
    import Synchronization
    import Windows_Kernel_Process
    @testable import Process

    extension Process.Spawn.Deadline {
        @Suite struct Test {
            @Suite struct Unit {}

            final class Gate: Sendable {
                let event: Windows.`32`.Kernel.Event

                init() throws(Process.Error) {
                    do throws(Windows.`32`.Kernel.Event.Error) {
                        event = try Windows.`32`.Kernel.Event()
                    } catch {
                        switch error {
                        case .platform(let code): throw .capture(code)
                        }
                    }
                }
            }
        }
    }

    extension Process.Spawn.Deadline.Test.Gate {
        func wait() {
            do throws(Windows.`32`.Kernel.Event.Error) {
                let signalled = try event.wait(timeout: UInt32.max)
                #expect(signalled)
            } catch {
                Issue.record("Gate wait failed: \(error)")
            }
        }

        func release() {
            do throws(Windows.`32`.Kernel.Event.Error) {
                try event.signal()
            } catch {
                Issue.record("Gate release failed: \(error)")
            }
        }
    }

    extension Process.Spawn.Deadline.Test.Unit {
        @Test(.timeLimit(.minutes(1)), arguments: [49, 50, 51])
        func `completion uses the deadline while the watcher is gated`(
            _ milliseconds: Int
        ) throws(Process.Error) {
            let gate = try Process.Spawn.Deadline.Test.Gate()
            let deadline = try Process.Spawn.Deadline(timeout: .milliseconds(50))
            let started = ContinuousClock().now
            try deadline.start(at: started) { gate.wait() }
            defer {
                gate.release()
                deadline.cancel()
            }
            let status = try deadline.finish(
                .exited(code: 17),
                observing: { started.advanced(by: .milliseconds(milliseconds)) },
                claiming: { gate.release() }
            )
            #expect(status == (milliseconds < 50 ? .exited(code: 17) : .signaled(signal: 9)))
        }
    }
#endif
