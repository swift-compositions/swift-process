import Testing

@testable import Process

enum `Process Tests` {}

extension `Process Tests` {
    @Suite
    struct Test {
        @Test
        func `Process.exit(_:) is reachable as a typed function value`() {

            let fn: (Int32) -> Never = Process.exit(_:)

            _ = fn
        }
    }
}
