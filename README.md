# swift-process

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Cross-platform subprocess spawning, output capture, and lifecycle management — without importing Foundation.

---

## Quick Start

Run a child process, capture both output streams, bound its runtime, and switch over a typed exit status:

```swift
import Process

let output = try Process.Spawn.run(
    Process.Spawn.Configuration(
        executable: "/usr/bin/git",
        arguments: ["status", "--porcelain"],
        stdout: .pipe,
        stderr: .pipe,
        workingDirectory: "/path/to/repo",
        timeout: .seconds(30)
    )
)

switch output.status {
case .exited(code: 0):
    let listing = String(decoding: output.stdout ?? [], as: UTF8.self)
    print(listing)
case .exited(let code):
    let diagnostics = String(decoding: output.stderr ?? [], as: UTF8.self)
    print("git failed (\(code)): \(diagnostics)")
case .signaled(let signal):
    print("killed by signal \(signal)")  // timeout expiry reports SIGKILL here
case .stopped(let signal):
    print("stopped by signal \(signal)")
}
```

Two behaviors in this example are easy to get wrong when driving `posix_spawn(3)` or `CreateProcessW` by hand:

- **Deadlock-free dual capture.** When both `stdout` and `stderr` are piped, the parent drains them concurrently via `poll(2)` on POSIX. A child that fills the kernel's pipe buffer (typically 64 KiB) on one stream while the parent is still reading the other completes instead of wedging — the classic two-pipe deadlock.
- **Bounded runtime.** A non-`nil` `timeout` arms a watchdog that sends `SIGKILL` when the deadline elapses (POSIX). The result reports `.signaled` with the platform's `SIGKILL` value, and bytes drained before the kill are preserved.

For spawn-then-wait control flow, `Process.Spawn.spawn(_:)` returns a `Process.Handle`. The handle is `~Copyable` and `wait()` consumes it, so a double wait — which would race on the kernel's already-drained status — is a compile-time error rather than a runtime `ECHILD`:

```swift
import Process

let handle = try Process.Spawn.spawn(
    Process.Spawn.Configuration(executable: "/usr/bin/make", arguments: ["-j8"])
)
// ... other work while the child runs ...
let status = try handle.wait()  // consumes the handle; a second wait() cannot compile
```

The bare `spawn(_:)` path supports inherited streams only; configurations that pipe streams, set a working directory, or set a timeout go through `run(_:)`.

---

## Installation

Add swift-process to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/swift-compositions/swift-process.git", branch: "main")
]
```

Add the product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Process", package: "swift-process")
    ]
)
```

### Requirements

- Swift 6.3+
- macOS 26+, iOS 26+, tvOS 26+, watchOS 26+, visionOS 26+, Linux, Windows

---

## Key Features

- **No Foundation import** — composes typed kernel syscall wrappers only; the module never imports Apple's Foundation framework
- **Typed throws end-to-end** — every throwing entry point throws `Process.Error`; no `any Error` escapes the API surface
- **Compiler-enforced single wait** — `Process.Handle` is `~Copyable` and `wait()` is `consuming`, making double-wait bugs unrepresentable
- **Concurrent pipe drain** — both-pipes capture on POSIX drains `stdout` and `stderr` via `poll(2)`, immune to the pipe-buffer deadlock
- **Timeout enforcement** — `SIGKILL` watchdog on POSIX with partial output preserved
- **Cross-platform mechanics** — `posix_spawn(3)` on Darwin and Linux (safe in multithreaded processes; no `fork`), `CreateProcessW` with explicit handle-inheritance lists on Windows

---

## Architecture

Single module, one namespace. The types a consumer touches:

| Type | Role |
|------|------|
| `Process.Spawn` | Entry points: `spawn(_:)` (handle out) and `run(_:)` (bundled result out) |
| `Process.Spawn.Configuration` | Executable, arguments, environment, per-stream disposition, working directory, timeout |
| `Process.Stream` | Stream disposition: `.inherit` or `.pipe` |
| `Process.Handle` | `~Copyable` reference to a running child; consumed by `wait()` |
| `Process.Output` | Exit status plus captured `stdout` / `stderr` bytes (`[UInt8]?`, uninterpreted) |
| `Process.Status` | `.exited(code:)`, `.signaled(signal:)`, `.stopped(signal:)` |
| `Process.Error` | Typed failure surface for spawn, wait, and capture |
| `Process.exit(_:)` | Immediate process termination (`_exit(2)` / `ExitProcess` semantics) |

Captured bytes are returned as `[UInt8]` without decoding; apply `String(decoding:as:)` when text is expected.

---

## Platform Support

| Platform | Spawn | Capture | Timeout |
|----------|-------|---------|---------|
| macOS / iOS / tvOS / watchOS / visionOS | `posix_spawn(3)` | Concurrent drain (both pipes) | `SIGKILL` watchdog |
| Linux | `posix_spawn(3)` | Concurrent drain (both pipes) | `SIGKILL` watchdog |
| Windows | `CreateProcessW` | Sequential drain | Not yet enforced (field accepted, currently a no-op) |

Current scope boundaries, verified as of the latest revision:

- `stdin: .pipe` is not yet supported; `run(_:)` throws `.streamPolicyUnsupported` when requested.
- On Windows, high-volume dual capture drains sequentially over ~4 KiB anonymous pipes; for large outputs capture one stream at a time.
- Dropping a `Handle` without waiting leaves the child as a zombie until the parent exits — the standard POSIX trade-off; the package does not silently reap.

---

## Error Handling

All throwing operations throw `Process.Error`:

```
Process.Error
├── .invalidPath(index:)         // interior NUL byte; index 0 = executable, 1...n = arguments, n+1... = environment
├── .spawn(_)                    // posix_spawn(3) / CreateProcessW failed (wrapped kernel error)
├── .wait(_)                     // waitpid(2) / WaitForSingleObject failed (wrapped kernel error)
├── .capture(_)                  // pipe creation, close, or drain failed (platform error code)
├── .streamPolicyUnsupported     // configuration requests a policy this entry point does not support
├── .unrecognizedStatus          // kernel returned a status outside the known classifications
└── .platformUnsupported         // no subprocess support on this platform
```

Exhaustive handling:

```swift
do throws(Process.Error) {
    let output = try Process.Spawn.run(configuration)
    // use output
} catch {
    switch error {
    case .invalidPath(let index):
        // reject the offending input (0 = executable, 1...n = arguments)
        break
    case .spawn(let kernelError), .wait(let kernelError):
        // inspect the wrapped POSIX / Win32 error
        _ = kernelError
    case .capture(let code):
        // pipe plumbing failed; code carries the platform error
        _ = code
    case .streamPolicyUnsupported, .unrecognizedStatus, .platformUnsupported:
        // configuration or platform mismatch
        break
    }
}
```

---

## Related Packages

- [swift-posix](https://github.com/swift-compositions/swift-posix) — POSIX kernel surface this package composes for spawning and waiting.
- [swift-windows](https://github.com/swift-compositions/swift-windows) — Win32 kernel surface backing the Windows path.
- [swift-kernel](https://github.com/swift-compositions/swift-kernel) — Cross-platform kernel facade; re-exported by this package for environment access (public, no tagged release yet).

---

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public release.*
<!-- END: discussion -->

---

## License

Apache 2.0. See [LICENSE](LICENSE.md) for details.
