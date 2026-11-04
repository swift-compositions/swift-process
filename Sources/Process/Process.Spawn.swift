internal import Strings

#if !os(Windows)
    internal import Path
    internal import Kernel
#endif

extension Process {

    public enum Spawn: Sendable {}
}

extension Process.Spawn {

    public static func spawn(
        _ configuration: Configuration
    ) throws(Process.Error) -> Process.Handle {
        try _checkSpawnSupports(configuration)

        #if !os(Windows)

            var actions = try _makeActions()
            let pid = try _spawnWithActions(configuration, actions: &actions)

            return Process.Handle(id: pid)
        #else

            let actions: Windows.`32`.Kernel.Process.Spawn.Actions
            do throws(Windows.`32`.Kernel.Process.Error) {
                actions = try Windows.`32`.Kernel.Process.Spawn.Actions()
            } catch {
                switch error {
                case .create(let code), .wait(let code):
                    throw .spawn(.create(code))

                case .platform(let err):
                    throw .spawn(.create(err.code))
                }
            }
            let result = try _spawnWithActions(configuration, actions: actions)
            return Process.Handle(processInfo: consume result)
        #endif
    }

    public static func run(
        _ configuration: Configuration
    ) throws(Process.Error) -> Process.Output {

        if configuration.stdin == .inherit
            && configuration.stdout == .inherit
            && configuration.stderr == .inherit
            && configuration.directory == nil
            && configuration.timeout == nil
        {
            let handle = try spawn(configuration)
            let status = try handle.wait()
            return Process.Output(status: status)
        }

        return try _runWithCapture(configuration)
    }
}

extension Process.Spawn {
    internal static func _checkSpawnSupports(
        _ configuration: Configuration
    ) throws(Process.Error) {
        switch configuration.stdin {
        case .inherit: break
        case .pipe: throw .streamPolicyUnsupported
        }
        switch configuration.stdout {
        case .inherit: break
        case .pipe: throw .streamPolicyUnsupported
        }
        switch configuration.stderr {
        case .inherit: break
        case .pipe: throw .streamPolicyUnsupported
        }
        if configuration.directory != nil {
            throw .streamPolicyUnsupported
        }
    }

    #if !os(Windows)
        internal static func _spawnVector(
            _ configuration: Configuration
        ) throws(Process.Error) -> [Swift.String] {
            let resolved = try Executable.resolve(configuration.executable)
            return [resolved, configuration.executable] + configuration.arguments
        }
        internal static func _spawnVectorIndex(_ index: Int) -> Int {
            index == 0 ? 0 : index - 1
        }
    #endif
    internal static func _flattenEnvironment(
        _ environment: [Swift.String: Swift.String]?
    ) -> [Swift.String] {
        guard let environment else {
            return _inheritedEnvironment()
        }
        return environment.keys.sorted().map { key in
            "\(key)=\(environment[key] ?? "")"
        }
    }
    internal static func _inheritedEnvironment() -> [Swift.String] {
        var result: [Swift.String] = []
        #if os(Windows)
            guard var iterator = Kernel.Environment.entries() else {
                return result
            }
        #else
            var iterator = Kernel.Environment.entries()
        #endif
        while let entry = iterator.next() {
            let name: Swift.String
            let value: Swift.String
            do throws(UTF8.ValidationError) {
                name = try Swift.String(entry.name)
                value = try Swift.String(entry.value)
            } catch {
                continue
            }
            result.append("\(name)=\(value)")
        }
        return result
    }
}

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
