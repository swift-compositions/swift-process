#if os(Windows)
    extension Process.Spawn.Deadline {
        internal struct State: Sendable {
            internal var started: ContinuousClock.Instant?
            internal var outcome: Outcome = .waiting
        }
    }
#endif
