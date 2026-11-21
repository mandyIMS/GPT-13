import Foundation

enum GPTUserAgentMode: Equatable {
    case standard
    case googleAuthentication
}

struct GPTUserAgentConfiguration: Equatable {
    static let unconfigured = GPTUserAgentConfiguration(
        mode: .standard,
        userAgentOverride: nil,
        platformOverride: nil,
        appVersionOverride: nil,
        oscpuOverride: nil,
        buildIDOverride: nil
    )

    let mode: GPTUserAgentMode
    let userAgentOverride: String?
    let platformOverride: String?
    let appVersionOverride: String?
    let oscpuOverride: String?
    let buildIDOverride: String?
}

struct GPTUserAgentPolicy {
    func configuration(for url: URL?, geckoVersion: String) -> GPTUserAgentConfiguration {
        let geckoMajorVersion = geckoVersion
            .split(whereSeparator: { !$0.isNumber })
            .first
            .map(String.init) ?? "0"

        guard isGoogleAuthenticationURL(url) else {
            if isGitHubURL(url) {
                // GitHub's bot check blocks the app in v3 while Safari
                // on the same IP, logged out, loads the sign-in page
                // fine — the difference is the browser identity, not
                // the network. The app reports Firefox for Android on
                // an iPhone, a mismatch bot detection looks for. For
                // github.com, identify as Safari on this iPhone
                // (iOS 16.1.2), the way Google sign-in already gets
                // its own identity below.
                return GPTUserAgentConfiguration(
                    mode: .standard,
                    userAgentOverride: "Mozilla/5.0 (iPhone; CPU iPhone OS 16_1_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Mobile/15E148 Safari/604.1",
                    platformOverride: "iPhone",
                    appVersionOverride: "5.0 (iPhone; CPU iPhone OS 16_1_2 like Mac OS X)",
                    oscpuOverride: "iPhone OS 16_1_2",
                    buildIDOverride: nil
                )
            }
            // Reynard identifies as Firefox for Android from the very first
            // request. Besides making the unusual iOS + Gecko combination
            // understandable to websites, this ensures a Google navigation
            // never starts with Gecko's native embedded-app identity while
            // the per-site override is still being applied.
            return GPTUserAgentConfiguration(
                mode: .standard,
                userAgentOverride: "Mozilla/5.0 (Android 15; Mobile; rv:\(geckoMajorVersion).0) "
                    + "Gecko/\(geckoMajorVersion).0 Firefox/\(geckoMajorVersion).0",
                platformOverride: "Linux armv81",
                appVersionOverride: "5.0 (Android 15)",
                oscpuOverride: "Linux armv81",
                buildIDOverride: nil
            )
        }

        let chromeMajorVersion = (Int(geckoMajorVersion) ?? 0) + 4

        // Match Reynard's Google compatibility profile. Google otherwise sees
        // the unusual iOS + Gecko combination and can reject the sign-in page
        // before the user reaches the account authorization step.
        let userAgent = "Mozilla/5.0 (Linux; Android 15; Nexus 5 Build/MRA58N) "
            + "FxQuantum/\(geckoMajorVersion).0 AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/\(chromeMajorVersion).0.0.0 Mobile Safari/537.36"

        return GPTUserAgentConfiguration(
            mode: .googleAuthentication,
            userAgentOverride: userAgent,
            platformOverride: "Linux armv81",
            appVersionOverride: "5.0 (Android 15)",
            oscpuOverride: "Linux armv81",
            buildIDOverride: nil
        )
    }

    private func isGoogleAuthenticationURL(_ url: URL?) -> Bool {
        guard let host = url?.host?
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
            return false
        }
        return host == "accounts.google.com"
    }

    private func isGitHubURL(_ url: URL?) -> Bool {
        guard let host = url?.host?
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
            return false
        }
        return host == "github.com" || host.hasSuffix(".github.com")
    }
}
