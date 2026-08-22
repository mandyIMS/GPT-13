import Foundation
import GeckoView

enum GPTSitePermissionStore {
    private static let defaultsKey = "GPTSitePermissions"

    static func decision(
        for permission: ContentPermission.Permission,
        host: String
    ) -> Bool? {
        let values = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool]
        return values?[key(for: permission, host: host)]
    }

    static func setDecision(
        _ allowed: Bool,
        for permission: ContentPermission.Permission,
        host: String
    ) {
        var values = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool] ?? [:]
        values[key(for: permission, host: host)] = allowed
        UserDefaults.standard.set(values, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func key(for permission: ContentPermission.Permission, host: String) -> String {
        "\(host.lowercased())|\(permission.rawValue)"
    }
}

enum GPTWebsiteDataClearDiagnostics {
    private static let isRunningKey = "GPTWebsiteDataClear.isRunning"
    private static let summaryKey = "GPTWebsiteDataClear.summary"

    static var summary: String {
        UserDefaults.standard.string(forKey: summaryKey) ?? "No clear attempt recorded."
    }

    static func markInterruptedAttemptIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: isRunningKey) else { return }
        let previous = defaults.string(forKey: summaryKey) ?? "an unknown step"
        record("Interrupted during: \(previous)", isRunning: false)
    }

    static func began(_ step: String) {
        record(step, isRunning: true)
    }

    static func completed(_ step: String) {
        record("Completed: \(step)", isRunning: false)
    }

    static func failed(_ step: String, error: Error) {
        record("Failed at \(step): \(error.localizedDescription)", isRunning: false)
    }

    static func scheduled() {
        record("Reset scheduled. Reopen GPT to clear the Gecko profile.", isRunning: false)
    }

    static func finished() {
        record("Completed successfully. The Gecko profile was removed before startup.", isRunning: false)
    }

    private static func record(_ summary: String, isRunning: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(isRunning, forKey: isRunningKey)
        defaults.set(summary, forKey: summaryKey)
        // Persist the breadcrumb before asking Gecko to mutate its profile so
        // it survives an abrupt process termination.
        defaults.synchronize()
    }
}

enum GPTWebsiteDataCleaner {
    private static let pendingProfileResetKey = "GPTWebsiteDataClear.pendingProfileReset"

    static func scheduleProfileReset() {
        UserDefaults.standard.set(true, forKey: pendingProfileResetKey)
        UserDefaults.standard.synchronize()
        GPTWebsiteDataClearDiagnostics.scheduled()
    }

    static func performPendingProfileReset(at profileRoot: URL) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: pendingProfileResetKey) else { return }

        GPTWebsiteDataClearDiagnostics.began("Removing the Gecko profile before startup")
        do {
            if FileManager.default.fileExists(atPath: profileRoot.path) {
                try FileManager.default.removeItem(at: profileRoot)
            }
            GPTSitePermissionStore.clear()
            defaults.set(false, forKey: pendingProfileResetKey)
            defaults.synchronize()
            GPTWebsiteDataClearDiagnostics.finished()
        } catch {
            GPTWebsiteDataClearDiagnostics.failed("Removing the Gecko profile before startup", error: error)
        }
    }
}
