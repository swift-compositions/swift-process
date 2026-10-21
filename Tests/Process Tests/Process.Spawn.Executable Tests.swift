import Testing

@testable import Process

extension Process.Spawn.Executable {

    @Suite
    struct Test {

        #if os(Windows)
            static let interpreter = "cmd"
            static let interpreterPath = "C:\\Windows\\System32\\cmd.exe"
            static func exitArguments(_ code: Int) -> [Swift.String] { ["/C", "exit \(code)"] }
            static let echoArguments = ["/C", "echo hello"]
            static let separator: Character = "\\"
        #else
            static let interpreter = "sh"
            static let interpreterPath = "/bin/sh"
            static func exitArguments(_ code: Int) -> [Swift.String] { ["-c", "exit \(code)"] }
            static let echoArguments = ["-c", "echo hello"]
            static let separator: Character = "/"
        #endif

        @Test
        func `Bare interpreter name resolves to a path containing a separator`() throws {
            let resolved = try Process.Spawn.Executable.resolve(Self.interpreter)
            #expect(resolved.contains(Self.separator))
            #expect(resolved.lowercased().contains(Self.interpreter))
        }

        @Test
        func `Value containing a separator is returned as-is`() throws {
            let resolved = try Process.Spawn.Executable.resolve(Self.interpreterPath)
            #expect(resolved == Self.interpreterPath)
        }

        @Test
        func `Bare name spawns through the fast path and reports the child's exit code`() throws {
            let output = try Process.Spawn.run(
                Process.Spawn.Configuration(
                    executable: Self.interpreter,
                    arguments: Self.exitArguments(3)
                )
            )
            #expect(output.status == .exited(code: 3))
        }

        @Test
        func `Bare name spawns through the capture path and stdout is drained`() throws {
            let output = try Process.Spawn.run(
                Process.Spawn.Configuration(
                    executable: Self.interpreter,
                    arguments: Self.echoArguments,
                    stdout: .pipe
                )
            )
            #expect(output.status == .exited(code: 0))
            let stdout = try #require(output.stdout)
            #expect(stdout.starts(with: Array("hello".utf8)))
        }

        @Test
        func `Unresolvable bare name throws executableNotFound naming the program`() throws {
            let name = "swift-process-no-such-program-4f9c1e"
            do throws(Process.Error) {
                _ = try Process.Spawn.Executable.resolve(name)
                Issue.record("expected throw, got success")
            } catch {
                #expect(error == .executableNotFound(name))
            }
            do throws(Process.Error) {
                _ = try Process.Spawn.run(Process.Spawn.Configuration(executable: name))
                Issue.record("expected throw, got success")
            } catch {
                #expect(error == .executableNotFound(name))
            }
        }

        @Test
        func `directories(in:) splits on the platform separator and preserves empty entries`() {
            #if os(Windows)
                let list = "C:\\one;C:\\two;;C:\\three"
                let expected: [Swift.Substring] = ["C:\\one", "C:\\two", "", "C:\\three"]
            #else
                let list = "/one:/two::/three"
                let expected: [Swift.Substring] = ["/one", "/two", "", "/three"]
            #endif
            #expect(Process.Spawn.Executable.directories(in: list) == expected)
        }

        @Test
        func `directories(in:) does not split on the other platform's separator`() {
            #if os(Windows)
                let foreign = "/one:/two"
            #else
                let foreign = "one;two"
            #endif
            #expect(Process.Spawn.Executable.directories(in: foreign).count == 1)
        }

        #if os(Windows)
            @Test
            func `PATHEXT supplies the .exe suffix for a bare Windows name`() throws {
                let resolved = try Process.Spawn.Executable.resolve("cmd")
                #expect(resolved.lowercased().hasSuffix("\\cmd.exe"))
            }

            @Test
            func `A bare Windows name that already carries .exe resolves too`() throws {
                let resolved = try Process.Spawn.Executable.resolve("cmd.exe")
                #expect(resolved.lowercased().hasSuffix("\\cmd.exe"))
            }
        #endif
    }
}
