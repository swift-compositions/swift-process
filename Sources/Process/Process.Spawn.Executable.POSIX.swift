#if !os(Windows)

    internal import Path
    internal import POSIX_Kernel

    extension Process.Spawn.Executable {

        @usableFromInline
        internal static var _listSeparator: Character { ":" }

        @usableFromInline
        internal static func _containsSeparator(_ executable: Swift.String) -> Bool {
            executable.contains("/")
        }

        @usableFromInline
        internal static func _environmentNamesMatch(_ key: Substring, _ name: Swift.String) -> Bool
        {
            key == name
        }

        @usableFromInline
        internal static func _searchPath(_ name: Swift.String) -> Swift.String? {
            guard let path = _environmentValue("PATH") else { return nil }
            for directory in _splitSearchList(path) {
                let candidate: Swift.String
                if directory.isEmpty {
                    candidate = name
                } else if directory.hasSuffix("/") {
                    candidate = Swift.String(directory) + name
                } else {
                    candidate = Swift.String(directory) + "/" + name
                }
                if _isExecutableFile(candidate) {
                    return candidate
                }
            }
            return nil
        }

        @usableFromInline
        internal static func _isExecutableFile(_ candidate: Swift.String) -> Bool {
            let stats: ISO_9945.Kernel.File.Stats
            do throws(Path.String.Error<ISO_9945.Kernel.File.Stats.Error>) {
                stats = try Path.scope(candidate) {
                    (
                        view: borrowing Path.Borrowed
                    ) throws(ISO_9945.Kernel.File.Stats.Error)
                        -> ISO_9945.Kernel.File.Stats in
                    try ISO_9945.Kernel.File.Stats.get(path: view)
                }
            } catch {
                return false
            }
            guard stats.type == .regular else { return false }
            let anyExecute: ISO_9945.Kernel.File.Permissions =
                .ownerExecute | .groupExecute | .otherExecute
            return (stats.permissions & anyExecute) != .none
        }
    }

#endif
