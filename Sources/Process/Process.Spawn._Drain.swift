#if os(Windows)
    extension Process.Spawn {
        @usableFromInline
        internal final class _Drain: @unchecked Sendable {
            @usableFromInline
            internal var result: Result<[UInt8], Process.Error> = .success([])

            @usableFromInline
            internal init() {}
        }
    }
#endif
