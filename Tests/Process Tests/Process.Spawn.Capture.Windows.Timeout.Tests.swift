#if os(Windows)
    import Testing
    import WinSDK
    @testable import Process

    extension Process.Spawn.Test {
        @Suite
        struct Integration {
            enum Streams: CaseIterable, Sendable {
                case inherited
                case stdout
                case stderr
                case both

                var output: Process.Stream {
                    switch self {
                    case .inherited, .stderr: .inherit
                    case .stdout, .both: .pipe
                    }
                }

                var error: Process.Stream {
                    switch self {
                    case .inherited, .stdout: .inherit
                    case .stderr, .both: .pipe
                    }
                }
            }
        }
    }

    extension Process.Spawn.Test.Integration {
        @Test(.timeLimit(.minutes(1)), arguments: Streams.allCases)
        func `fifty milliseconds bounds every capture policy`(
            _ streams: Streams
        ) throws(Process.Error) {
            let start = ContinuousClock().now
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "ping -n 7 127.0.0.1 >nul"],
                    stdout: streams.output,
                    stderr: streams.error,
                    timeout: .milliseconds(50)
                )
            )
            #expect(output.status == .signaled(signal: 9))
            #expect(ContinuousClock().now - start < .seconds(3))
            #expect((output.stdout != nil) == (streams.output == .pipe))
            #expect((output.stderr != nil) == (streams.error == .pipe))
        }

        @Test(.timeLimit(.minutes(1)))
        func `fast exit preserves its code and cancels the deadline`() throws(Process
            .Error)
        {
            let start = ContinuousClock().now
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "echo fast & exit /b 17"],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: .seconds(20)
                )
            )
            #expect(output.status == .exited(code: 17))
            #expect(ContinuousClock().now - start < .seconds(5))
            #expect(Swift.String(decoding: output.stdout ?? [], as: UTF8.self).contains("fast"))
        }

        @Test(.timeLimit(.minutes(1)))
        func `partial output survives a timeout`() throws(Process
            .Error)
        {
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: [
                        "/D", "/C",
                        "echo before-out & echo before-err 1>&2 & ping -n 7 127.0.0.1 >nul",
                    ],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: .seconds(1)
                )
            )
            #expect(output.status == .signaled(signal: 9))
            #expect(
                Swift.String(decoding: output.stdout ?? [], as: UTF8.self).contains("before-out"))
            #expect(
                Swift.String(decoding: output.stderr ?? [], as: UTF8.self).contains("before-err"))
        }

        @Test(.timeLimit(.minutes(1)))
        func `deadline survives root exit until inherited pipes close`()
            throws(Process
            .Error)
        {
            let start = ContinuousClock().now
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: [
                        "/D", "/C",
                        "start /b ping.exe -n 7 127.0.0.1 & echo root-exited & exit /b 0",
                    ],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: .seconds(1)
                )
            )
            #expect(output.status == .signaled(signal: 9))
            #expect(ContinuousClock().now - start < .seconds(3))
            #expect(
                Swift.String(decoding: output.stdout ?? [], as: UTF8.self).contains("root-exited"))
        }

        @Test(.timeLimit(.minutes(1)))
        func `timeout preserves an unrelated process`() throws(Process.Error) {
            let bystander = try Process.Spawn.spawn(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "ping -n 3 127.0.0.1 >nul & exit /b 29"]
                )
            )
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "ping -n 7 127.0.0.1 >nul"],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: .milliseconds(50)
                )
            )
            let status = try bystander.wait()
            #expect(output.status == .signaled(signal: 9))
            #expect(status == .exited(code: 29))
        }

        @Test(.timeLimit(.minutes(1)), arguments: [Duration.zero, .milliseconds(-1)])
        func `nonpositive timeout never waits indefinitely`(
            _ timeout: Duration
        ) throws(Process.Error) {
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "ping -n 7 127.0.0.1 >nul"],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: timeout
                )
            )
            #expect(output.status == .signaled(signal: 9))
        }

        @Test(.timeLimit(.minutes(1)))
        func `normal timed return preserves a continuing descendant`() throws(Process.Error) {
            let parent = unsafe GetCurrentProcessId()
            let script = #"""
                Add-Type @'
                using System;
                using System.Runtime.InteropServices;
                public static class Handles {
                    [DllImport("kernel32.dll", SetLastError=true)]
                    public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
                    [DllImport("kernel32.dll", SetLastError=true)]
                    public static extern bool DuplicateHandle(IntPtr source, IntPtr handle,
                        IntPtr target, out IntPtr copy, uint access, bool inherit, uint options);
                    [DllImport("kernel32.dll")]
                    public static extern IntPtr GetCurrentProcess();
                    [DllImport("kernel32.dll")]
                    public static extern bool CloseHandle(IntPtr handle);
                }
                '@
                $target = [Handles]::OpenProcess(0x40, $false, \#(parent))
                if ($target -eq [IntPtr]::Zero) { exit 2 }
                $s = New-Object System.Diagnostics.ProcessStartInfo
                $s.FileName = 'C:\Windows\System32\ping.exe'
                $s.Arguments = '-n 21 127.0.0.1'
                $s.UseShellExecute = $false
                $s.CreateNoWindow = $true
                $s.RedirectStandardOutput = $true
                $s.RedirectStandardError = $true
                $p = [System.Diagnostics.Process]::Start($s)
                $copy = [IntPtr]::Zero
                $ok = [Handles]::DuplicateHandle([Handles]::GetCurrentProcess(), $p.Handle,
                    $target, [ref]$copy, 0, $false, 2)
                [void][Handles]::CloseHandle($target)
                if (!$ok) { $p.Kill(); $p.WaitForExit(); exit 3 }
                [Console]::WriteLine($copy.ToInt64())
                exit 17
                """#
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"#,
                    arguments: ["-NoProfile", "-NonInteractive", "-Command", script],
                    stdout: .pipe, stderr: .pipe, timeout: .seconds(20)
                )
            )
            #expect(output.status == .exited(code: 17))
            let handles = Swift.String(decoding: output.stdout ?? [], as: UTF8.self)
                .split(whereSeparator: { $0.isWhitespace })
            guard let value = handles.first, let raw = UInt(value),
                let descendant = unsafe UnsafeMutableRawPointer(bitPattern: raw)
            else {
                Issue.record("The fixture did not return its owned descendant handle")
                return
            }
            defer {
                _ = unsafe TerminateProcess(descendant, 1)
                _ = unsafe WaitForSingleObject(descendant, INFINITE)
                _ = unsafe CloseHandle(descendant)
            }
            let active = unsafe WaitForSingleObject(descendant, 0)
            #expect(active == UInt32(WAIT_TIMEOUT))
        }

        @Test(.timeLimit(.minutes(1)))
        func `nil timeout preserves normal completion`() throws(Process.Error) {
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\cmd.exe"#,
                    arguments: ["/D", "/C", "echo complete & exit /b 17"],
                    stdout: .pipe,
                    stderr: .pipe
                )
            )
            #expect(output.status == .exited(code: 17))
            #expect(Swift.String(decoding: output.stdout ?? [], as: UTF8.self).contains("complete"))
        }
    }
#endif
