#if os(Windows)
    internal import Windows_Kernel_Thread
    internal import Windows_Kernel_Process

    extension Process.Spawn.Capture {
        internal struct Hooks: Sendable {
            internal var termination:
                @Sendable (borrowing Windows.`32`.Kernel.Process.Job) throws(Process.Error.Kernel)
                    -> Void = { try $0.terminate(code: 1) }
            internal var launch:
                @Sendable (@escaping @Sendable () -> Void) throws(Windows.`32`.Kernel.Thread.Error)
                    -> Windows.`32`.Kernel.Thread.Handle = {
                        try Windows.`32`.Kernel.Thread.create($0)
                    }
            internal var read:
                @Sendable (UInt, Process.Spawn._StdioSlot) -> Result<[UInt8], Process.Error> = {
                    raw, _ in
                    Process.Spawn._drainRawHandle(raw)
                }
            internal var waited: @Sendable (Result<Process.Status, Process.Error>) -> Void = { _ in
            }
        }
    }
#endif
