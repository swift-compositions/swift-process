#if !os(Windows)
    internal import Kernel

    extension Process.Spawn {
        internal struct Watchdog: ~Copyable {
            internal var thread: ISO_9945.Kernel.Thread.Handle?
            internal var shutdown: ISO_9945.Kernel.Pipe.Descriptors?
            internal init() {
                self.thread = nil
                self.shutdown = nil
            }
        }
    }
#endif
