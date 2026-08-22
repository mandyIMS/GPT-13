import Foundation

enum GPTNavigationDecision: Equatable {
    case allowInApp
    case openExternally
    case deny
}

enum GPTNavigationTarget: Equatable {
    case current
    case newWindow
}

struct GPTNavigationContext: Equatable {
    let isTopLevel: Bool
    let target: GPTNavigationTarget
    let hasUserGesture: Bool
    let isRedirect: Bool
    let triggerURL: URL?
    let authenticationFlowActive: Bool
}

struct GPTNavigationPolicy {
    static let homeURL = URL(string: "https://chatgpt.com/")!

    private static let chatGPTHosts: Set<String> = [
        "chatgpt.com",
        "chat.openai.com",
    ]

    private static let authenticationHosts: Set<String> = [
        "auth.openai.com",
        "auth0.openai.com",
        "accounts.google.com",
        "appleid.apple.com",
        "login.live.com",
        "login.microsoftonline.com",
    ]

    private static let challengeHosts: Set<String> = [
        "challenges.cloudflare.com",
    ]

    private static let chatGPTAssetDomains: Set<String> = [
        "oaistatic.com",
        "oaiusercontent.com",
    ]

    private static let externallyHandledSchemes: Set<String> = [
        "mailto",
        "tel",
        "sms",
        "facetime",
        "facetime-audio",
    ]

    func decision(for url: URL?, context: GPTNavigationContext) -> GPTNavigationDecision {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              !scheme.isEmpty else {
            return .deny
        }

        // The restriction is deliberately top-level only. ChatGPT relies on
        // cross-origin APIs, scripts, frames, images and challenge resources.
        guard context.isTopLevel else {
            return .allowInApp
        }

        if scheme == "about" || scheme == "blob" || scheme == "data" {
            return .allowInApp
        }

        if Self.externallyHandledSchemes.contains(scheme) {
            return context.hasUserGesture ? .openExternally : .deny
        }

        guard scheme == "http" || scheme == "https",
              let host = normalizedHost(url) else {
            return .deny
        }

        if isChatGPTHost(host) {
            return .allowInApp
        }

        if isAuthenticationHost(host) {
            if context.authenticationFlowActive || beganFromChatGPT(context.triggerURL) {
                return .allowInApp
            }
            return context.hasUserGesture ? .openExternally : .deny
        }

        if isChallengeHost(host) {
            return beganFromTrustedFlow(context.triggerURL) ? .allowInApp : .deny
        }

        if isChatGPTAssetHost(host) {
            return beganFromTrustedFlow(context.triggerURL) ? .allowInApp : .deny
        }

        // A link explicitly activated by the user is safe to hand to the
        // system browser. Silent redirects to an unrelated site are blocked.
        if context.hasUserGesture || context.target == .newWindow {
            return .openExternally
        }

        return .deny
    }

    func beginsAuthenticationFlow(_ url: URL?) -> Bool {
        guard let url,
              let host = normalizedHost(url) else {
            return false
        }
        return isAuthenticationHost(host)
    }

    func completesAuthenticationFlow(_ url: URL?) -> Bool {
        guard let url,
              let host = normalizedHost(url) else {
            return false
        }
        return isChatGPTHost(host)
    }

    private func beganFromChatGPT(_ triggerURL: URL?) -> Bool {
        guard let triggerURL,
              let host = normalizedHost(triggerURL) else {
            return false
        }
        return isChatGPTHost(host)
    }

    private func beganFromTrustedFlow(_ triggerURL: URL?) -> Bool {
        guard let triggerURL,
              let host = normalizedHost(triggerURL) else {
            return false
        }
        return isChatGPTHost(host) || isAuthenticationHost(host) || isChallengeHost(host)
    }

    private func normalizedHost(_ url: URL) -> String? {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty else {
            return nil
        }
        return host
    }

    private func isChatGPTHost(_ host: String) -> Bool {
        Self.chatGPTHosts.contains(host) || host.hasSuffix(".chatgpt.com")
    }

    private func isAuthenticationHost(_ host: String) -> Bool {
        Self.authenticationHosts.contains(host)
    }

    private func isChallengeHost(_ host: String) -> Bool {
        Self.challengeHosts.contains(host)
    }

    private func isChatGPTAssetHost(_ host: String) -> Bool {
        Self.chatGPTAssetDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }
}
