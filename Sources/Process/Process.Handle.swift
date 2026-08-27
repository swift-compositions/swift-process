#if !os(Windows)
    public import POSIX_Kernel
#endif

#if os(Windows)
    internal import Windows_Kernel_Process
    internal import WinSDK
#endif

extension Process {

    public struct Handle: ~Copyable, Sendable {
        #if !os(Windows)

            public let processID: ISO_9945.Kernel.Process.ID
        #else

            @usableFromInline
            internal var _spawnResult: Windows.`32`.Kernel.Process.Spawn.Result

            public let processID: UInt32
        #endif

        #if !os(Windows)
            @usableFromInline
            internal init(processID: ISO_9945.Kernel.Process.ID) {
                self.processID = processID
            }
        #else

            @usableFromInline
            internal init(processInfo: consuming Windows.`32`.Kernel.Process.Spawn.Result) {

                self.processID = processInfo.processID
                self._spawnResult = consume processInfo
            }
        #endif

        #if !os(Windows)

            public consuming func wait() throws(Process.Error) -> Process.Status {
                let pid = self.processID
                let result: ISO_9945.Kernel.Process.Wait.Result?
                do throws(ISO_9945.Kernel.Process.Error) {
                    result = try POSIX.Kernel.Process.Wait.wait(.process(pid))
                } catch {
                    throw .wait(error)
                }
                guard let status = result?.status,
                    let lifted = Process.Status(status)
                else {
                    throw .unrecognizedStatus
                }
                return lifted
            }
        #else

            public consuming func wait() throws(Process.Error) -> Process.Status {

                let processHandle = unsafe UnsafeMutableRawPointer(
                    bitPattern: self._spawnResult.processHandle._rawValue
                )

                guard let processHandle else {
                    throw .unrecognizedStatus
                }

                let waitResult = unsafe WaitForSingleObject(processHandle, INFINITE)
                guard waitResult == WAIT_OBJECT_0 else {
                    let code: Error.Error.Code = .win32(GetLastError())
                    throw .wait(.create(code))
                }

                var exitCode: DWORD = 0
                let got = unsafe GetExitCodeProcess(processHandle, &exitCode)

                guard got else {
                    let code: Error.Error.Code = .win32(GetLastError())
                    throw .wait(.create(code))
                }

                return .exited(code: Int32(bitPattern: exitCode))
            }
        #endif
    }
}
