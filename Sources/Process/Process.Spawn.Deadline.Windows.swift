#if os(Windows)
    internal import Synchronization
    internal import Windows_Kernel_Process
    internal import Windows_Kernel_Thread

    extension Process.Spawn {
        @usableFromInline
        internal final class Deadline: Sendable {
            private let containment: Mutex<Windows.`32`.Kernel.Process.Job?>
            private let event: Windows.`32`.Kernel.Event
            private let termination:
                @Sendable (borrowing Windows.`32`.Kernel.Process.Job) throws(Process.Error.Kernel)
                    -> Void
            private let timeout: Duration
            private let state = Mutex<State>(.init())
            private let thread = Mutex<Windows.`32`.Kernel.Thread.Handle?>(nil)

            internal init(
                timeout: Duration,
                termination:
                    @escaping @Sendable (borrowing Windows.`32`.Kernel.Process.Job)
                    throws(Process.Error.Kernel) -> Void = { try $0.terminate(code: 1) }
            ) throws(Process.Error) {
                do throws(Process.Error.Kernel) {
                    let job = try Windows.`32`.Kernel.Process.Job()
                    try job.limit(.killOnClose)
                    self.containment = Mutex(consume job)
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
                self.termination = termination
            }
        }
    }

    extension Process.Spawn.Deadline {
        internal func start(
            at started: ContinuousClock.Instant = ContinuousClock().now,
            before: @escaping @Sendable () -> Void = {}
        ) throws(Process.Error) {
            state.withLock { $0.started = started }
            do throws(Windows.`32`.Kernel.Thread.Error) {
                let watcher = try Windows.`32`.Kernel.Thread.create { [self] in
                    before()
                    watch(since: started)
                }
                thread.withLock { $0 = watcher }
            } catch {
                switch error {
                case .create(let failure): throw .capture(failure.code)
                }
            }
        }

        internal func finish(
            _ status: Process.Status,
            observing: () -> ContinuousClock.Instant = { ContinuousClock().now },
            claiming: () -> Void = {}
        ) throws(Process.Error) -> Process.Status {
            let expired = state.withLock {
                guard case .waiting = $0.outcome, let started = $0.started else { return false }
                if started.duration(to: observing()) >= timeout {
                    $0.outcome = .expired
                    return true
                }
                $0.outcome = .complete
                return false
            }
            claiming()
            if expired { terminate() }
            try wake()
            join()
            switch state.withLock({ $0.outcome }) {
            case .complete:
                do throws(Process.Error.Kernel) {
                    try job {
                        (job: borrowing Windows.`32`.Kernel.Process.Job)
                            throws(Process.Error.Kernel) in
                        try job.limit([])
                    }
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
            let terminate = state.withLock {
                switch $0.outcome {
                case .complete: return false
                case .waiting:
                    $0.outcome = .cancelled
                    return true
                case .expired, .failure, .cancelled: return true
                }
            }
            if terminate { self.terminate() }
            do throws(Process.Error) {
                try wake()
            } catch {
                state.withLock { $0.outcome = .failure(error) }
            }
            join()
        }

        private func watch(since started: ContinuousClock.Instant) {
            guard timeout > .zero else {
                expire(failure: nil)
                return
            }
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
            let terminate = state.withLock {
                guard case .waiting = $0.outcome else { return false }
                $0.outcome = failure.map(Outcome.failure) ?? .expired
                return true
            }
            guard terminate else { return }
            self.terminate()
        }

        internal func job<Result: ~Copyable>(
            _ body: (borrowing Windows.`32`.Kernel.Process.Job) throws(Process.Error.Kernel) ->
                Result
        ) throws(Process.Error.Kernel) -> Result {
            try containment.withLock {
                (job: inout Windows.`32`.Kernel.Process.Job?)
                    throws(Process.Error.Kernel) -> Result in
                switch job {
                case .some(let job): return try body(job)
                case .none: throw .create(.win32(6))
                }
            }
        }

        private func terminate() {
            let failure = containment.withLock {
                (job: inout Windows.`32`.Kernel.Process.Job?)
                    -> Process.Error? in
                let failure: Process.Error?
                switch job {
                case .some(let owned):
                    do throws(Process.Error.Kernel) {
                        try termination(owned)
                        failure = nil
                    } catch {
                        failure = Self.failure(error)
                    }
                case .none: return nil
                }
                if let failure {
                    job = nil
                    return failure
                }
                return nil
            }
            if let failure { state.withLock { $0.outcome = .failure(failure) } }
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
