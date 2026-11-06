public import Path

extension Process.Spawn {

    public struct Configuration: Sendable {

        public let executable: Swift.String

        public let arguments: [Swift.String]

        public let environment: [Swift.String: Swift.String]?

        public let stdin: Process.Stream

        public let stdout: Process.Stream

        public let stderr: Process.Stream

        public let directory: Path::Path?

        public let timeout: Duration?

        public init(
            executable: Swift.String,
            arguments: [Swift.String] = [],
            environment: [Swift.String: Swift.String]? = nil,
            stdin: Process.Stream = .inherit,
            stdout: Process.Stream = .inherit,
            stderr: Process.Stream = .inherit,
            directory: Path::Path? = nil,
            timeout: Duration? = nil
        ) {
            self.executable = executable
            self.arguments = arguments
            self.environment = environment
            self.stdin = stdin
            self.stdout = stdout
            self.stderr = stderr
            self.directory = directory
            self.timeout = timeout
        }
    }
}
