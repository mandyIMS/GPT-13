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
    /// The user tapped something a few seconds ago, so a redirect that
    /// follows it is part of that tap (a tracking link, a short link, a
    /// login hop) rather than a silent redirect.
    let recentUserGesture: Bool
}

/// A website the app can open as its main page.
struct GPTSite: Equatable, Hashable {
    let name: String
    let url: URL

    var host: String {
        return url.host?.lowercased() ?? ""
    }
}

enum GPTSiteStore {
    static let builtInSites: [GPTSite] = [
        GPTSite(name: "Muse", url: URL(string: "https://muse.ai/")!),
        GPTSite(name: "Claude", url: URL(string: "https://claude.ai/")!),
        GPTSite(name: "Gemini", url: URL(string: "https://gemini.google.com/")!),
        GPTSite(name: "Grok", url: URL(string: "https://grok.com/")!),
        GPTSite(name: "GitHub", url: URL(string: "https://github.com/")!),
        GPTSite(name: "ChatGPT", url: URL(string: "https://chatgpt.com/")!),
    ]

    private static let selectedSiteURLKey = "GPTSelectedSiteURL"
    private static let customSiteURLsKey = "GPTCustomSiteURLs"
    private static let defaults = UserDefaults.standard

    static var customSites: [GPTSite] {
        let stored = defaults.stringArray(forKey: customSiteURLsKey) ?? []
        return stored.compactMap { string in
            guard let url = URL(string: string), let host = url.host, !host.isEmpty else {
                return nil
            }
            return GPTSite(name: host, url: url)
        }
    }

    static var allSites: [GPTSite] {
        return builtInSites + customSites
    }

    /// The site the app opens. A stored selection wins; otherwise the
    /// build's baked-in default site (Info.plist `GPTDefaultSiteURL`) is
    /// used; otherwise it falls back to Muse. A stored site that no longer
    /// exists (for example after it was deleted) is ignored.
    static var selectedSite: GPTSite {
        if let stored = defaults.string(forKey: selectedSiteURLKey),
           let storedHost = URL(string: stored)?.host?.lowercased(),
           let site = allSites.first(where: { $0.host == storedHost }) {
            return site
        }
        if let baked = defaultSite(
            forDefaultURLString: Bundle.main.object(forInfoDictionaryKey: "GPTDefaultSiteURL") as? String
        ) {
            return baked
        }
        return builtInSites[0]
    }

    /// The site baked into this build via Info.plist `GPTDefaultSiteURL`,
    /// if it names a site the app knows. Each per-site variant sets it so
    /// it opens to its own site on first launch. Unknown hosts and bad
    /// values return nil and the app falls back to Muse. A baked-in custom
    /// URL only resolves once that custom site exists in the app's list.
    static func defaultSite(forDefaultURLString string: String?) -> GPTSite? {
        guard let string,
              let host = URL(string: string)?.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        return allSites.first(where: { $0.host == host })
    }

    static func select(_ site: GPTSite) {
        defaults.set(site.url.absoluteString, forKey: selectedSiteURLKey)
    }

    /// The built-in or custom site for a host, if one already exists.
    static func existingSite(forHost host: String) -> GPTSite? {
        let normalized = host.lowercased()
        return allSites.first(where: { $0.host == normalized })
    }

    static func isCustomSite(_ site: GPTSite) -> Bool {
        return customSites.contains(site)
    }

    /// Normalizes what the user typed into a site URL, or returns nil when it
    /// has no host. A missing scheme defaults to https; an explicit scheme
    /// (for example http for a self-hosted page) is kept as typed.
    static func site(from input: String) -> GPTSite? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme),
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return GPTSite(name: host, url: url)
    }

    static func addCustomSite(_ site: GPTSite) {
        var urls = defaults.stringArray(forKey: customSiteURLsKey) ?? []
        urls.removeAll { string in
            URL(string: string)?.host?.lowercased() == site.host
        }
        urls.append(site.url.absoluteString)
        defaults.set(urls, forKey: customSiteURLsKey)
    }

    static func removeCustomSite(_ site: GPTSite) {
        var urls = defaults.stringArray(forKey: customSiteURLsKey) ?? []
        urls.removeAll { $0 == site.url.absoluteString }
        defaults.set(urls, forKey: customSiteURLsKey)
    }

    static var customHosts: Set<String> {
        return Set(customSites.map { $0.host })
    }
}

/// Deep links of the form `muse13v3://<host>`, opened from a Home Screen
/// shortcut, jump straight to one of the app's sites (built-in or custom).
/// Unknown hosts are ignored: the app stays on the current site and nothing
/// is added to the site list.
enum GPTDeepLink {
    static let scheme = "muse13v3"

    static func site(for url: URL) -> GPTSite? {
        guard url.scheme?.lowercased() == scheme,
              var host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("www.") {
            host = String(host.dropFirst("www.".count))
        }
        return GPTSiteStore.existingSite(forHost: host)
    }
}

struct GPTNavigationPolicy {
    static var homeURL: URL {
        return GPTSiteStore.selectedSite.url
    }

    private static let builtInHosts: Set<String> = [
        "muse.ai",
        "claude.ai",
        "claude.com",
        "gemini.google.com",
        "grok.com",
        "github.com",
        "github.io",
        "githubusercontent.com",
        "chatgpt.com",
        "chat.openai.com",
    ]

    private static let authenticationHosts: Set<String> = [
        "accounts.google.com",
        "appleid.apple.com",
        "login.live.com",
        "login.microsoftonline.com",
        "x.com",
        "auth.openai.com",
        "auth0.openai.com",
        "auth.anthropic.com",
    ]

    private static let challengeHosts: Set<String> = [
        "challenges.cloudflare.com",
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

        // The restriction is deliberately top-level only. The selected site
        // relies on cross-origin APIs, scripts, frames, images and challenge
        // resources.
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

        if isAllowedSiteHost(host) {
            return .allowInApp
        }

        if isAuthenticationHost(host) {
            // A login host is only ever reached through a login: a tap,
            // a new window, a redirect right after a tap, or a hop
            // inside a login flow. Those all stay in the app. The old
            // fallback sent a tapped login link to the system browser,
            // which breaks the login (the return hop has no way back),
            // and a login hop whose trigger was not an allowed site
            // ended on a blank page. Only a silent login-host
            // navigation, with no tap and no login behind it, is
            // blocked, and it is blocked in-app, never sent out.
            if context.authenticationFlowActive
                || beganFromTrustedFlow(context.triggerURL)
                || context.hasUserGesture
                || context.target == .newWindow
                || context.recentUserGesture {
                return .allowInApp
            }
            return .deny
        }

        if isChallengeHost(host) {
            return beganFromTrustedFlow(context.triggerURL) ? .allowInApp : .deny
        }

        // A link the user tapped, or a new window they asked for, opens in
        // the app, whatever site it points to. A redirect that follows a
        // tap within a few seconds is part of that tap (a tracking link, a
        // short link, a login hop). A redirect chain that is part of a login
        // flow and started on one of the app's sites (or a login host) also
        // stays in the app, so a login that passes through extra hosts does
        // not end on a blank page. Only a silent redirect from somewhere
        // else, with no tap behind it, is blocked. (A plain navigation with
        // no gesture flag is NOT allowed on the trigger alone: a site the
        // user removed from their list must stay blocked, even when the
        // navigation starts from a page they trust.)
        if context.hasUserGesture || context.target == .newWindow {
            return .allowInApp
        }
        if context.recentUserGesture {
            return .allowInApp
        }
        if context.authenticationFlowActive && beganFromTrustedFlow(context.triggerURL) {
            return .allowInApp
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
        return isAllowedSiteHost(host)
    }

    private func beganFromAllowedSite(_ triggerURL: URL?) -> Bool {
        guard let triggerURL,
              let host = normalizedHost(triggerURL) else {
            return false
        }
        return isAllowedSiteHost(host)
    }

    private func beganFromTrustedFlow(_ triggerURL: URL?) -> Bool {
        guard let triggerURL,
              let host = normalizedHost(triggerURL) else {
            return false
        }
        return isAllowedSiteHost(host) || isAuthenticationHost(host) || isChallengeHost(host)
    }

    private func normalizedHost(_ url: URL) -> String? {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty else {
            return nil
        }
        return host
    }

    private func isAllowedSiteHost(_ host: String) -> Bool {
        return isBuiltInHost(host) || isCustomHost(host)
    }

    private func isBuiltInHost(_ host: String) -> Bool {
        return Self.builtInHosts.contains(host)
            || Self.builtInHosts.contains { host.hasSuffix("." + $0) }
    }

    private func isCustomHost(_ host: String) -> Bool {
        let custom = GPTSiteStore.customHosts
        return custom.contains(host)
            || custom.contains { host.hasSuffix("." + $0) }
    }

    private func isAuthenticationHost(_ host: String) -> Bool {
        Self.authenticationHosts.contains(host)
    }

    private func isChallengeHost(_ host: String) -> Bool {
        Self.challengeHosts.contains(host)
    }
}
