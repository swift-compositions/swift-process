#if os(Windows)
    extension Process.Spawn {
        internal static func capture(
            _ configuration: Configuration,
            timeout: Duration,
            hooks: Capture.Hooks = .init()
        ) throws(Process.Error) -> Process.Output {
            switch (configuration.stdout, configuration.stderr) {
            case (.inherit, .inherit):
                let actions = try _makeActions()
                let deadline = try Deadline(timeout: timeout, termination: hooks.termination)
                let result = try _spawnWithActions(
                    configuration,
                    actions: actions,
                    deadline: deadline
                )
                var capture = Capture(result: consume result, deadline: deadline, hooks: hooks)
                defer { capture.cancel() }
                return Process.Output(status: try capture.finish())

            case (.pipe, .inherit):
                var actions = try _makeActions()
                let pipe = try _makePipe()
                try _wireChildHandle(pipe.write, into: &actions, slot: .stdout)
                let deadline = try Deadline(timeout: timeout, termination: hooks.termination)
                let result = try _spawnWithActions(
                    configuration,
                    actions: actions,
                    deadline: deadline
                )
                var capture = Capture(result: consume result, deadline: deadline, hooks: hooks)
                defer { capture.cancel() }
                let output = try capture.read(try _closeWriteEnd(pipe), stream: .stdout)
                return Process.Output(status: try capture.finish(), stdout: output)

            case (.inherit, .pipe):
                var actions = try _makeActions()
                let pipe = try _makePipe()
                try _wireChildHandle(pipe.write, into: &actions, slot: .stderr)
                let deadline = try Deadline(timeout: timeout, termination: hooks.termination)
                let result = try _spawnWithActions(
                    configuration,
                    actions: actions,
                    deadline: deadline
                )
                var capture = Capture(result: consume result, deadline: deadline, hooks: hooks)
                defer { capture.cancel() }
                let output = try capture.read(try _closeWriteEnd(pipe), stream: .stderr)
                return Process.Output(status: try capture.finish(), stderr: output)

            case (.pipe, .pipe):
                var actions = try _makeActions()
                let outputPipe = try _makePipe()
                let errorPipe = try _makePipe()
                try _wireChildHandle(outputPipe.write, into: &actions, slot: .stdout)
                try _wireChildHandle(errorPipe.write, into: &actions, slot: .stderr)
                let deadline = try Deadline(timeout: timeout, termination: hooks.termination)
                let result = try _spawnWithActions(
                    configuration,
                    actions: actions,
                    deadline: deadline
                )
                var capture = Capture(result: consume result, deadline: deadline, hooks: hooks)
                defer { capture.cancel() }
                let output = try _closeWriteEnd(outputPipe)
                let error = try _closeWriteEnd(errorPipe)
                try capture.start(consume error)
                let captured = try capture.read(output, stream: .stdout)
                let errors = try capture.collect()
                return Process.Output(
                    status: try capture.finish(),
                    stdout: captured,
                    stderr: errors
                )
            }
        }
    }
#endif
