import Testing

@testable import Process

extension Process {
    @Suite("Process.exit structural tests")
    struct Test {
        @Test
        func `Process.exit(_:) is reachable as a typed function value`() {

            let fn: (Int32) -> Never = Process.exit(_:)

            _ = fn
        }
    }
}
