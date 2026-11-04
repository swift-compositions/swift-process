# swift-process

Use this package when your Swift program needs to run another program and wait for it, optionally capturing what it prints or giving it a time limit, on macOS, Linux and Windows alike. Start from `Process.Spawn.run(_:)` with a `Process.Spawn.Configuration`. Use `Process.Spawn.spawn(_:)` when you want the `Process.Handle` and wait for it later yourself. For the raw spawn calls of one platform, use swift-posix or swift-windows.

## Laws

- `Process.Spawn.spawn(_:)` only runs children that inherit all three standard streams and the current directory. A piped stream or a working directory makes it fail with `streamPolicyUnsupported`, and it ignores `timeout`. `Process.Spawn.run(_:)` supports all of these except a piped stdin, which always fails the same way.
- A stream that is inherited comes back as nil in `Process.Output`. A piped stream comes back as every byte the child wrote. stdout and stderr are read at the same time, so a child that fills one pipe while you wait on the other does not deadlock.
- When `timeout` runs out, the child is killed and `Process.Spawn.run(_:)` still returns normally, with the status `.signaled(signal: 9)` on every platform. Output captured before the kill is kept. A zero or negative timeout kills the child at once. On Windows the whole job is killed, including processes the child started.
- An executable that contains a path separator is used as written. A bare name is looked up in the `PATH` of the current process, not in the configured environment, and the child receives the name as you wrote it as its first argument. On POSIX an empty `PATH` entry means the current directory, and a match must be a regular file with an execute bit set. On Windows the extensions in `PATHEXT` are tried, by default `.COM`, `.EXE`, `.BAT` and `.CMD`.
- A nil `environment` passes on the current process's environment. On POSIX, entries that aren't valid UTF-8 are left out. A dictionary replaces the environment completely.
- On macOS a child does not inherit the parent's other open file descriptors, only its standard streams.
- On Windows each argument is quoted for the command line: an argument that is empty or contains whitespace or a quote is put in quotes, embedded quotes are escaped, and backslashes are doubled only where they come right before a quote, including the closing one.
