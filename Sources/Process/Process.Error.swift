#if !os(Windows)
    internal import POSIX_Kernel
#else
    internal import Windows_Kernel_Process
#endif

extension Process {

    public enum Error: Swift.Error, Sendable, Equatable, Hashable {

        #if !os(Windows)
            public typealias Kernel = ISO_9945.Kernel.Process.Error
        #else
            public typealias Kernel = Windows.`32`.Kernel.Process.Error
        #endif

        case invalidPath(index: Int)

        case executableNotFound(Swift.String)

        case spawn(Kernel)

        case wait(Kernel)

        case unrecognizedStatus

        case capture(Error::Error.Code)

        case streamPolicyUnsupported

        case platformUnsupported
    }
}
