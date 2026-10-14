#if os(Windows)
    internal import Synchronization
    internal import Windows_Kernel_Process
    internal import Windows_Kernel_Thread

    extension Process.Spawn {
        @usableFromInline
        internal final class Deadline: Sendable {
            internal let job: Windows.`32`.Kernel.Process.Job
            private let event: Windows.`32`.Kernel.Event
            private let timeout: Duration
            private let outcome = Mutex<Outcome>(.waiting)
            private let thread = Mutex<Windows.`32`.Kernel.Thread.Handle?>(nil)

            internal init(timeout: Duration) throws(Process.Error) {
                do throws(Process.Error.Kernel) {
                    let job = try Windows.`32`.Kernel.Process.Job()
                    try job.limit(.killOnClose)
                    self.job = job
                } catch {
                    throw Self.failure(error)
                }
                do throws(Windows.`32`.Kernel.Event.Error) {
                    self.event = try Windows.`32`.Kernel.Event()
                } catch {
                    switch error {
                    case .platform(let code): throw .capture(code)
                    }
                }
                self.timeout = timeout
            }
        }
    }

    extension Process.Spawn.Deadline {
        internal func start() throws(Process.Error) {
            let started = ContinuousClock().now
            do throws(Windows.`32`.Kernel.Thread.Error) {
                let watcher = try Windows.`32`.Kernel.Thread.create { [self] in
                    watch(since: started)
                }
                thread.withLock { $0 = watcher }
            } catch {
                switch error {
                case .create(let failure): throw .capture(failure.code)
                }
            }
        }

        internal func finish(_ status: Process.Status) throws(Process.Error) -> Process.Status {
            outcome.withLock {
                if case .waiting = $0 { $0 = .complete }
            }
            try wake()
            join()
            switch outcome.withLock({ $0 }) {
            case .complete:
                do throws(Process.Error.Kernel) {
                    try job.limit([])
                } catch {
                    throw Self.failure(error)
                }
                return status
            case .expired: return .signaled(signal: 9)
            case .failure(let error): throw error
            case .waiting, .cancelled: throw .unrecognizedStatus
            }
        }

        internal func cancel() {
            let terminate = outcome.withLock {
                switch $0 {
                case .complete: return false
                case .waiting:
                    $0 = .cancelled
                    return true
                case .expired, .failure, .cancelled: return true
                }
            }
            if terminate {
                do throws(Process.Error.Kernel) {
                    try job.terminate(code: 1)
                } catch {
                    outcome.withLock { $0 = .failure(Self.failure(error)) }
                }
            }
            do throws(Process.Error) {
                try wake()
            } catch {
                outcome.withLock { $0 = .failure(error) }
            }
            join()
        }

        private func watch(since started: ContinuousClock.Instant) {
            while true {
                let remaining = timeout - started.duration(to: ContinuousClock().now)
                do throws(Windows.`32`.Kernel.Event.Error) {
                    if try event.wait(timeout: Self.milliseconds(remaining)) { return }
                } catch {
                    switch error {
                    case .platform(let code): expire(failure: .capture(code))
                    }
                    return
                }
                if started.duration(to: ContinuousClock().now) >= timeout {
                    expire(failure: nil)
                    return
                }
            }
        }

        private func expire(failure: Process.Error?) {
            let terminate = outcome.withLock {
                guard case .waiting = $0 else { return false }
                $0 = failure.map(Outcome.failure) ?? .expired
                return true
            }
            guard terminate else { return }
            do throws(Process.Error.Kernel) {
                try job.terminate(code: 1)
            } catch {
                outcome.withLock { $0 = .failure(Self.failure(error)) }
            }
        }

        private func wake() throws(Process.Error) {
            do throws(Windows.`32`.Kernel.Event.Error) {
                try event.signal()
            } catch {
                switch error {
                case .platform(let code): throw .capture(code)
                }
            }
        }

        private func join() {
            let watcher = thread.withLock {
                let watcher = $0
                $0 = nil
                return watcher
            }
            watcher?.join()
        }

        private static func failure(_ error: Process.Error.Kernel) -> Process.Error {
            switch error {
            case .create(let code), .wait(let code): return .capture(code)
            case .platform(let failure): return .capture(failure.code)
            }
        }

        private static func milliseconds(_ remaining: Duration) -> UInt32 {
            guard remaining > .zero else { return 0 }
            let (seconds, attoseconds) = remaining.components
            guard seconds < Int64(UInt32.max / 1000) else { return UInt32.max - 1 }
            let fraction = (attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
            return UInt32(min(seconds * 1000 + fraction, Int64(UInt32.max - 1)))
        }
    }
#endif
