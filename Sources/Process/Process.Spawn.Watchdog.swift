#if !os(Windows)
    internal import Kernel

    extension Process.Spawn {
        internal struct Watchdog: ~Copyable {
            internal var thread: ISO_9945.Kernel.Thread.Handle?
            internal var shutdownWriteFd: Int32
            internal var shutdownReadFd: Int32
            internal init() {
                self.thread = nil
                self.shutdownWriteFd = -1
                self.shutdownReadFd = -1
            }
        }
    }
#endif
