#if os(Windows)
    internal import Windows_Kernel_Process
    internal import Windows_Kernel_Thread

    extension Process.Spawn {
        internal struct Capture: ~Copyable {
            private var process: Process.Handle?
            private let deadline: Deadline
            private let hooks: Hooks
            private let drain = _Drain()
            private var reader: Windows.`32`.Kernel.Thread.Handle?
            private var descriptor: Windows.`32`.Kernel.Descriptor?

            internal init(
                result: consuming Windows.`32`.Kernel.Process.Spawn.Result,
                deadline: Deadline,
                hooks: Hooks
            ) {
                self.process = Process.Handle(processInfo: consume result)
                self.deadline = deadline
                self.hooks = hooks
            }
        }
    }

    extension Process.Spawn.Capture {
        internal mutating func start(
            _ descriptor: consuming Windows.`32`.Kernel.Descriptor
        ) throws(Process.Error) {
            let raw = descriptor._rawValue
            let drain = self.drain
            let read = hooks.read
            do throws(Windows.`32`.Kernel.Thread.Error) {
                reader = try hooks.launch {
                    drain.result = read(raw, .stderr)
                }
                self.descriptor = consume descriptor
            } catch {
                switch error {
                case .create(let failure): throw .capture(failure.code)
                }
            }
        }

        internal func read(
            _ descriptor: consuming Windows.`32`.Kernel.Descriptor,
            stream: Process.Spawn._StdioSlot
        ) throws(Process.Error) -> [UInt8] {
            let result = hooks.read(descriptor._rawValue, stream)
            _ = consume descriptor
            return try result.get()
        }

        internal mutating func collect() throws(Process.Error) -> [UInt8] {
            join()
            return try drain.result.get()
        }

        internal mutating func finish() throws(Process.Error) -> Process.Status {
            let process = self.process.take()
            guard let process = consume process else { throw .unrecognizedStatus }
            let status = try process.wait()
            hooks.waited(.success(status))
            return try deadline.finish(status)
        }

        internal mutating func cancel() {
            deadline.cancel()
            join()
            let process = self.process.take()
            if let process = consume process {
                do throws(Process.Error) {
                    hooks.waited(.success(try process.wait()))
                } catch {
                    hooks.waited(.failure(error))
                }
            }
        }

        private mutating func join() {
            let reader = self.reader
            self.reader = nil
            reader?.join()
            descriptor = nil
        }
    }
#endif
