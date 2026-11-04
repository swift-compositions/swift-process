import Testing

@testable import Process

extension Process.Spawn {
    @Suite
    struct `Edge Case` {

        @Test
        func `A simple token with no whitespace or quotes passes through unchanged`() {
            #expect(Process.Spawn._quoteWindowsCommandLineArgument("hello") == "hello")
            #expect(
                Process.Spawn._quoteWindowsCommandLineArgument("C:\\Windows\\System32\\cmd.exe")
                    == "C:\\Windows\\System32\\cmd.exe"
            )
        }

        @Test
        func `An argument containing a space is wrapped in quotes rather than naively space-joined`() {

            #expect(Process.Spawn._quoteWindowsCommandLineArgument("two words") == "\"two words\"")
        }

        @Test
        func `An empty argument is quoted so it still occupies its own argv slot`() {
            #expect(Process.Spawn._quoteWindowsCommandLineArgument("") == "\"\"")
        }

        @Test
        func `An embedded double quote is escaped, not passed through raw`() {

            #expect(
                Process.Spawn._quoteWindowsCommandLineArgument("say \"hi\"") == "\"say \\\"hi\\\"\""
            )
        }

        @Test
        func `A trailing backslash run is doubled before the closing quote`() {

            #expect(Process.Spawn._quoteWindowsCommandLineArgument("a\\ b\\") == "\"a\\ b\\\\\"")
        }

        @Test
        func `A backslash run immediately before an embedded quote is doubled-plus-one, then the quote is escaped`() {

            #expect(Process.Spawn._quoteWindowsCommandLineArgument("a\\\"b") == "\"a\\\\\\\"b\"")
        }

        @Test
        func `A backslash run not adjacent to a quote is left literal`() {

            #expect(
                Process.Spawn._quoteWindowsCommandLineArgument("C:\\Program Files\\App")
                    == "\"C:\\Program Files\\App\""
            )
        }

        @Test
        func `The executable token itself is quoted when it contains a space, not just the arguments`() {

            #expect(
                Process.Spawn._quoteWindowsCommandLineArgument("C:\\Program Files\\App\\app.exe")
                    == "\"C:\\Program Files\\App\\app.exe\""
            )
        }
    }
}
