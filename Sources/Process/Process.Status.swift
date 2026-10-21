#if !os(Windows)
    internal import Kernel
#endif

extension Process {

    public enum Status: Sendable, Equatable, Hashable {

        case exited(code: Int32)

        case signaled(signal: Int32)

        case stopped(signal: Int32)
    }
}

#if !os(Windows)
    extension Process.Status {

        @usableFromInline
        internal init?(_ status: ISO_9945.Kernel.Process.Status) {
            if status.exited, let code = status.exit.code {
                self = .exited(code: code)
            } else if status.signaled, let signal = status.terminating.signal {
                self = .signaled(signal: signal.rawValue)
            } else if status.stopped, let signal = status.stop.signal {
                self = .stopped(signal: signal.rawValue)
            } else {
                return nil
            }
        }
    }
#endif
