#if os(Windows)
    extension Process.Spawn.Deadline {
        internal enum Outcome: Sendable {
            case waiting
            case complete
            case expired
            case cancelled
            case failure(Process.Error)
        }
    }
#endif
