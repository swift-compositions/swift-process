#if os(Windows)

    internal import Windows_Kernel_File
    internal import WinSDK

    extension Process.Spawn.Executable {

        @usableFromInline
        internal static var _listSeparator: Character { ";" }

        @usableFromInline
        internal static let _defaultExtensions: [Substring] = [".COM", ".EXE", ".BAT", ".CMD"]

        @usableFromInline
        internal static func _containsSeparator(_ executable: Swift.String) -> Bool {
            executable.utf16.contains { unit in

                unit == 0x5C || unit == 0x2F || unit == 0x3A
            }
        }

        @usableFromInline
        internal static func _environmentNamesMatch(_ key: Substring, _ name: Swift.String) -> Bool {
            key.count == name.count && key.uppercased() == name.uppercased()
        }

        @usableFromInline
        internal static func _searchPath(_ name: Swift.String) -> Swift.String? {
            guard let path = _environmentValue("PATH") else { return nil }
            let extensions = _extensions()

            let hasExtension = name.utf16.contains(0x2E)
            for directory in _splitSearchList(path) where !directory.isEmpty {
                let base: Swift.String
                if directory.hasSuffix("\\") || directory.hasSuffix("/") {
                    base = Swift.String(directory) + name
                } else {
                    base = Swift.String(directory) + "\\" + name
                }
                if hasExtension, _isExecutableFile(base) {
                    return base
                }
                for ext in extensions {
                    let candidate = base + ext
                    if _isExecutableFile(candidate) {
                        return candidate
                    }
                }
            }
            return nil
        }

        @usableFromInline
        internal static func _extensions() -> [Substring] {
            guard let pathext = _environmentValue("PATHEXT") else {
                return _defaultExtensions
            }
            let entries = _splitSearchList(pathext).filter { !$0.isEmpty }
            return entries.isEmpty ? _defaultExtensions : entries
        }

        @usableFromInline
        internal static func _isExecutableFile(_ candidate: Swift.String) -> Bool {
            var units: [WCHAR] = Array(candidate.utf16)
            units.append(0)
            return unsafe units.withUnsafeBufferPointer {
                (buffer: UnsafeBufferPointer<WCHAR>) -> Bool in
                guard let base = unsafe buffer.baseAddress else { return false }
                guard let attributes = unsafe Windows.`32`.Kernel.File.getAttributes(path: base)
                else {
                    return false
                }
                return !attributes.contains(.directory)
            }
        }
    }

#endif
