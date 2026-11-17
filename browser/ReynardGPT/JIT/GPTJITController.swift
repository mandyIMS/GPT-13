import Darwin
import Foundation

enum GPTJITState: Equatable {
    case waiting
    case enabled
    case unavailable
    case failed(String)

    var description: String {
        switch self {
        case .waiting: return "Waiting for Gecko content process"
        case .enabled: return "Enabled (TrollStore ptrace helper)"
        case .unavailable: return "Unavailable: TrollStore entitlement missing"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}

final class GPTJITController {
    static let shared = GPTJITController()

    private let queue = DispatchQueue(
        label: "com.mandyims.muse13.jit",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private var storedState: GPTJITState = .waiting
    private var attachedPIDs: Set<Int32> = []

    var state: GPTJITState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedState
    }

    private init() {}

    func start() {
#if !targetEnvironment(simulator)
        if !getEntitlementValue("com.apple.private.security.no-sandbox") {
            setState(.unavailable)
        }
#endif

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(childProcessDidStart(_:)),
            name: Notification.Name("GeckoRuntime.ChildProcessDidStart"),
            object: nil
        )
    }

    @objc private func childProcessDidStart(_ notification: Notification) {
        guard let pidNumber = notification.userInfo?["pid"] as? NSNumber else { return }
        let pid = pidNumber.int32Value
        let processType = (notification.userInfo?["processType"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard pid > 0, processType == "tab" else {
            report(pid: pid, enabled: false)
            return
        }

#if targetEnvironment(simulator)
        // The simulator already permits executable JIT mappings. Gecko's
        // content process still waits for the same parent-process handshake
        // used on a TrollStore device, so acknowledge it without invoking the
        // device-only ptrace helper.
        setState(.enabled)
        report(pid: pid, enabled: true)
        return
#else
        guard getEntitlementValue("com.apple.private.security.no-sandbox") else {
            setState(.unavailable)
            report(pid: pid, enabled: false)
            return
        }

        queue.async { [weak self] in
            self?.attach(pid: pid)
        }
#endif
    }

    private func attach(pid: Int32) {
        guard !attachedPIDs.contains(pid) else { return }
        attachedPIDs.insert(pid)

        guard let helperPath = Bundle.main.path(forAuxiliaryExecutable: "ts_ptrace_jit")
                ?? Bundle.main.path(forResource: "ts_ptrace_jit", ofType: nil) else {
            setState(.failed("ts_ptrace_jit is missing"))
            report(pid: pid, enabled: false)
            return
        }

        var result = spawnRoot(helperPath, [String(pid)])
        if Self.shouldRetryFromTemporaryDirectory(result) {
            do {
                let temporaryHelper = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ts_ptrace_jit", isDirectory: false)
                try? FileManager.default.removeItem(at: temporaryHelper)
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: helperPath),
                    to: temporaryHelper
                )
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: temporaryHelper.path
                )
                result = spawnRoot(temporaryHelper.path, [String(pid)])
            } catch {
                setState(.failed("Unable to stage ptrace helper: \(error.localizedDescription)"))
                report(pid: pid, enabled: false)
                return
            }
        }
        guard result == 0 else {
            setState(.failed("ptrace helper exited with status \(result)"))
            report(pid: pid, enabled: false)
            return
        }

        setState(.enabled)
        report(pid: pid, enabled: true)
    }

    private static func shouldRetryFromTemporaryDirectory(_ result: Int32) -> Bool {
        result == EACCES || result == ENOENT || result == ENOEXEC || result == 126 || result == 127
    }

    private func report(pid: Int32, enabled: Bool) {
        guard pid > 0 else { return }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = DeviceOSVersion(
            majorVersion: Int32(version.majorVersion),
            minorVersion: Int32(version.minorVersion),
            patchVersion: Int32(version.patchVersion)
        )
        let runtimeInfo = JITRuntimeInfo(
            hasTXMSupport: 0,
            deviceOSVersion: osVersion
        )
        ReportJITStatusForChild(pid, enabled, runtimeInfo)
    }

    private func setState(_ newState: GPTJITState) {
        stateLock.lock()
        storedState = newState
        stateLock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("ReynardGPT.JITStateDidChange"),
                object: nil
            )
        }
    }
}
