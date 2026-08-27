internal import Strings

#if !os(Windows)
    internal import Path
    internal import POSIX_Kernel
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

            let vector = try _spawnVector(configuration)
            let envp = _flattenEnvironment(configuration.environment)

            let pid: ISO_9945.Kernel.Process.ID
            do throws(Path.String.Error<ISO_9945.Kernel.Process.Error>) {
                pid = try unsafe Path.scope.array(vector, envp) {
                    (
                        vectorPtr: UnsafePointer<UnsafePointer<Path.Char>?>,
                        envpPtr: UnsafePointer<UnsafePointer<Path.Char>?>
                    ) throws(ISO_9945.Kernel.Process.Error) -> ISO_9945.Kernel.Process.ID in
                    try unsafe POSIX.Kernel.Process.Spawn.spawn(
                        path: unsafe vectorPtr[0]!,
                        argv: unsafe vectorPtr + 1,
                        envp: envpPtr
                    )
                }
            } catch {
                switch error {
                case .conversion(.interiorNUL(let index)):
                    throw .invalidPath(index: _spawnVectorIndex(index))

                case .body(let posixError):
                    throw .spawn(posixError)
                }
            }

            return Process.Handle(processID: pid)
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
            && configuration.workingDirectory == nil
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

    @usableFromInline
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
        if configuration.workingDirectory != nil {
            throw .streamPolicyUnsupported
        }
    }

    #if !os(Windows)

        @usableFromInline
        internal static func _spawnVector(
            _ configuration: Configuration
        ) throws(Process.Error) -> [Swift.String] {
            let resolved = try Executable.resolve(configuration.executable)
            return [resolved, configuration.executable] + configuration.arguments
        }

        @usableFromInline
        internal static func _spawnVectorIndex(_ index: Int) -> Int {
            index == 0 ? 0 : index - 1
        }
    #endif

    @usableFromInline
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

    @usableFromInline
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
