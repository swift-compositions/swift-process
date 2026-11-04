#if !os(Windows)
    public import Kernel
    internal import POSIX_Kernel_File

    extension Process {

        public final class Reader: Sendable {

            public let processID: ISO_9945.Kernel.Process.ID

            private let descriptor: ISO_9945.Kernel.Descriptor

            internal init(
                processID: ISO_9945.Kernel.Process.ID,
                descriptor: consuming ISO_9945.Kernel.Descriptor
            ) {
                self.processID = processID
                self.descriptor = descriptor
            }
        }
    }

    extension Process.Reader {

        public func read(upTo limit: UInt) throws(Process.Error) -> [UInt8] {
            var chunk = [UInt8](repeating: 0, count: Int(limit))
            do throws(ISO_9945.Kernel.IO.Read.Error) {
                let count = try chunk.withUnsafeMutableBufferPointer {
                    (raw: inout UnsafeMutableBufferPointer<UInt8>) throws(ISO_9945.Kernel.IO.Read.Error) -> Int in
                    try unsafe POSIX.Kernel.IO.Read.read(descriptor, into: UnsafeMutableRawBufferPointer(raw))
                }
                chunk.removeLast(chunk.count - count)
                return chunk
            } catch {
                throw .capture(error.code)
            }
        }

        public func terminate() throws(Process.Error) {
            do throws(ISO_9945.Kernel.Process.Error) {
                try POSIX.Kernel.Process.Kill.kill(processID, .kill)
            } catch {
                throw .spawn(error)
            }
        }

        public func wait() throws(Process.Error) -> Process.Status {
            try Process.Handle(processID: processID).wait()
        }
    }

    extension Process.Spawn {

        public static func reading(_ configuration: Configuration) throws(Process.Error) -> Process.Reader {
            guard configuration.stdin == .inherit, configuration.stdout == .pipe, configuration.stderr == .inherit,
                configuration.timeout == nil
            else { throw .streamPolicyUnsupported }
            var actions = try _makeActions()
            let pipe = try _makePipe()
            do throws(ISO_9945.Kernel.Process.Error) {
                try actions.add(dup2: pipe.write, to: .stdout)
                try actions.add(close: .init(pipe.read))
            } catch {
                throw .spawn(error)
            }
            try _addChdir(&actions, cwd: configuration.workingDirectory)
            let pid = try _spawnWithActions(configuration, actions: &actions)
            return Process.Reader(processID: pid, descriptor: try _closeWriteEnd(pipe))
        }
    }
#endif
