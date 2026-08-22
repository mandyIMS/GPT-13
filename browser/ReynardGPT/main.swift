import Darwin
import Foundation
import GeckoView

private func configurePersistentGeckoProfile() {
    guard let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first else {
        return
    }

    let profileRoot = applicationSupport
        .appendingPathComponent("ReynardGPT", isDirectory: true)
        .appendingPathComponent("Gecko", isDirectory: true)

    do {
        // Website-data APIs terminate this iOS Gecko build while its profile
        // is live. A requested reset is therefore performed before Gecko or
        // any content process can open the profile databases.
        GPTWebsiteDataCleaner.performPendingProfileReset(at: profileRoot)
        try FileManager.default.createDirectory(
            at: profileRoot,
            withIntermediateDirectories: true
        )
        setenv("MOZ_APP_DATA", profileRoot.path, 1)
        setenv("MOZ_LOCAL_APP_DATA", profileRoot.path, 1)
    } catch {
        NSLog("ReynardGPT: unable to prepare persistent Gecko profile: %@", error.localizedDescription)
    }
}

configurePersistentGeckoProfile()
setenv("REYNARD_CJK_COMPOSITION_CARET_OVERLAY", "1", 1)
setenv("REYNARD_SUPPRESS_INLINE_KEYBOARD_REPLACEMENTS", "1", 1)
GPTJITController.shared.start()
GeckoRuntime.main(argc: CommandLine.argc, argv: CommandLine.unsafeArgv)
