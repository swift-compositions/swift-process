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
                Swift.String(decoding: output.stdout ?? [], as: UTF8.self).contains("before-out")
            )
            #expect(
                Swift.String(decoding: output.stderr ?? [], as: UTF8.self).contains("before-err")
            )
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
                Swift.String(decoding: output.stdout ?? [], as: UTF8.self).contains("root-exited")
            )
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

        private static func descendant(
            parent: UInt32,
            inheritingCapturedPipes: Bool
        ) -> String {
            #"""
            Add-Type @'
            using System;
            using System.Runtime.InteropServices;
            using System.Text;
            public static class Handles {
                [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
                public struct StartupInfo {
                    public uint cb;
                    public string reserved;
                    public string desktop;
                    public string title;
                    public uint x;
                    public uint y;
                    public uint xSize;
                    public uint ySize;
                    public uint xCountChars;
                    public uint yCountChars;
                    public uint fillAttribute;
                    public uint flags;
                    public ushort showWindow;
                    public ushort reserved2;
                    public IntPtr reservedBytes;
                    public IntPtr standardInput;
                    public IntPtr standardOutput;
                    public IntPtr standardError;
                }
                [StructLayout(LayoutKind.Sequential)]
                public struct ProcessInformation {
                    public IntPtr process;
                    public IntPtr thread;
                    public uint processID;
                    public uint threadID;
                }
                [DllImport("kernel32.dll", SetLastError=true)]
                public static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
                [DllImport("kernel32.dll", EntryPoint="CreateProcessW", ExactSpelling=true,
                    SetLastError=true, CharSet=CharSet.Unicode)]
                public static extern bool CreateProcess(string application, StringBuilder command,
                    IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles,
                    uint flags, IntPtr environment, string directory, ref StartupInfo startup,
                    out ProcessInformation process);
                [DllImport("kernel32.dll", SetLastError=true)]
                public static extern bool DuplicateHandle(IntPtr source, IntPtr handle,
                    IntPtr target, out IntPtr copy, uint access, bool inherit, uint options);
                [DllImport("kernel32.dll")]
                public static extern IntPtr GetCurrentProcess();
                [DllImport("kernel32.dll")]
                public static extern bool CloseHandle(IntPtr handle);
                public static IntPtr Start(bool inheritHandles) {
                    var startup = new StartupInfo();
                    startup.cb = (uint)Marshal.SizeOf(startup);
                    ProcessInformation process;
                    var executable = @"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe";
                    var command = new StringBuilder(
                        "powershell.exe -NoLogo -NoProfile -NonInteractive " +
                        "-Command Start-Sleep -Seconds 20");
                    if (!CreateProcess(executable, command, IntPtr.Zero, IntPtr.Zero,
                        inheritHandles, 0x08000000, IntPtr.Zero, null, ref startup, out process)) {
                        return IntPtr.Zero;
                    }
                    CloseHandle(process.thread);
                    return process.process;
                }
            }
            '@
            $target = [Handles]::OpenProcess(0x40, $false, \#(parent))
            if ($target -eq [IntPtr]::Zero) { exit 2 }
            $process = [Handles]::Start($\#(inheritingCapturedPipes ? "true" : "false"))
            if ($process -eq [IntPtr]::Zero) { exit 8 }
            $copy = [IntPtr]::Zero
            $ok = [Handles]::DuplicateHandle([Handles]::GetCurrentProcess(), $process,
                $target, [ref]$copy, 0, $false, 2)
            [void][Handles]::CloseHandle($target)
            [void][Handles]::CloseHandle($process)
            if (!$ok) { exit 3 }
            [Console]::WriteLine($copy.ToInt64())
            exit 17
            """#
        }

        @Test(.timeLimit(.minutes(1)))
        func `normal timed return preserves a continuing descendant`() throws(Process.Error) {
            let parent = unsafe GetCurrentProcessId()
            let script = Self.descendant(parent: parent, inheritingCapturedPipes: false)
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"#,
                    arguments: ["-NoProfile", "-NonInteractive", "-Command", script],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: .seconds(20)
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
        func `unused inherited capture handles retain the deadline`() throws(Process.Error) {
            let parent = unsafe GetCurrentProcessId()
            let script = Self.descendant(parent: parent, inheritingCapturedPipes: true)
            let output = try Process.Spawn.run(
                .init(
                    executable: #"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"#,
                    arguments: ["-NoProfile", "-NonInteractive", "-Command", script],
                    stdout: .pipe,
                    stderr: .pipe,
                    timeout: .seconds(20)
                )
            )
            #expect(output.status == .signaled(signal: 9))
            let handles = String(decoding: output.stdout ?? [], as: UTF8.self)
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
            let active = unsafe WaitForSingleObject(descendant, 5_000)
            #expect(active == UInt32(WAIT_OBJECT_0))
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
