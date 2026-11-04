#if !os(Windows)
    import Process
    import Testing

    extension Process.Reader {
        @Suite struct Test {
            @Suite struct Unit {}
            @Suite struct `Edge Case` {}
        }
    }

    extension Process.Reader.Test.Unit {
        static func reader(_ script: Swift.String) throws -> Process.Reader {
            try Process.Spawn.reading(
                Process.Spawn.Configuration(executable: "/bin/sh", arguments: ["-c", script], stdout: .pipe)
            )
        }

        @Test
        func `a running child's output can be read before it exits`() throws {
            let reader = try Self.reader("printf first; exec sleep 60")
            #expect(try reader.read(upTo: 16) == Array("first".utf8))
            try reader.terminate()
            #expect(try reader.wait() == .signaled(signal: 9))
        }

        @Test
        func `reading to the end gives every byte, then nothing, and the child's status`() throws {
            let reader = try Self.reader("printf abc; printf def; exit 3")
            var bytes: [UInt8] = []
            while case let chunk = try reader.read(upTo: 2), !chunk.isEmpty { bytes += chunk }
            #expect(bytes == Array("abcdef".utf8))
            #expect(try reader.read(upTo: 2).isEmpty)
            #expect(try reader.wait() == .exited(code: 3))
        }
    }

    extension Process.Reader.Test.`Edge Case` {
        @Test
        func `a configuration that doesn't pipe only stdout is refused`() {
            #expect(throws: Process.Error.self) {
                try Process.Spawn.reading(Process.Spawn.Configuration(executable: "/bin/sh"))
            }
            #expect(throws: Process.Error.self) {
                try Process.Spawn.reading(
                    Process.Spawn.Configuration(executable: "/bin/sh", stdout: .pipe, stderr: .pipe)
                )
            }
        }
    }
#endif
