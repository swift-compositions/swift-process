import Testing

@testable import Process

extension Process.Spawn {
    @Suite
    struct `Edge Case` {

        @Test("A simple token with no whitespace or quotes passes through unchanged")
        func `plainTokenPassesThroughUnchanged`() {
            #expect(Process.Spawn._quoteWindowsCommandLineArgument("hello") == "hello")
            #expect(
                Process.Spawn._quoteWindowsCommandLineArgument("C:\\Windows\\System32\\cmd.exe")
                    == "C:\\Windows\\System32\\cmd.exe"
            )
        }

        @Test(
            "An argument containing a space is wrapped in quotes rather than naively space-joined"
        )
        func `argumentContainingSpaceIsQuoted`() {

            #expect(Process.Spawn._quoteWindowsCommandLineArgument("two words") == "\"two words\"")
        }

        @Test("An empty argument is quoted so it still occupies its own argv slot")
        func `emptyArgumentIsQuoted`() {
            #expect(Process.Spawn._quoteWindowsCommandLineArgument("") == "\"\"")
        }

        @Test("An embedded double quote is escaped, not passed through raw")
        func `embeddedQuoteIsEscaped`() {

            #expect(
                Process.Spawn._quoteWindowsCommandLineArgument("say \"hi\"") == "\"say \\\"hi\\\"\""
            )
        }

        @Test("A trailing backslash run is doubled before the closing quote")
        func `trailingBackslashRunIsDoubled`() {

            #expect(Process.Spawn._quoteWindowsCommandLineArgument("a\\ b\\") == "\"a\\ b\\\\\"")
        }

        @Test(
            "A backslash run immediately before an embedded quote is doubled-plus-one, then the quote is escaped"
        )
        func `backslashRunBeforeEmbeddedQuoteIsDoubledPlusOne`() {

            #expect(Process.Spawn._quoteWindowsCommandLineArgument("a\\\"b") == "\"a\\\\\\\"b\"")
        }

        @Test("A backslash run not adjacent to a quote is left literal")
        func `backslashRunNotAdjacentToQuoteStaysLiteral`() {

            #expect(
                Process.Spawn._quoteWindowsCommandLineArgument("C:\\Program Files\\App")
                    == "\"C:\\Program Files\\App\""
            )
        }

        @Test(
            "The executable token itself is quoted when it contains a space, not just the arguments"
        )
        func `executableTokenIsQuotedWhenItContainsASpace`() {

            #expect(
                Process.Spawn._quoteWindowsCommandLineArgument("C:\\Program Files\\App\\app.exe")
                    == "\"C:\\Program Files\\App\\app.exe\""
            )
        }
    }
}
