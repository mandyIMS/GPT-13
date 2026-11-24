import Foundation

private var failures: [String] = []

private func expect(
    _ name: String,
    _ actual: GPTNavigationDecision,
    _ expected: GPTNavigationDecision
) {
    if actual != expected {
        failures.append("\(name): expected \(expected), got \(actual)")
    }
}

private func expectUserAgentMode(
    _ name: String,
    _ actual: GPTUserAgentMode,
    _ expected: GPTUserAgentMode
) {
    if actual != expected {
        failures.append("\(name): expected \(expected), got \(actual)")
    }
}

private func context(
    topLevel: Bool = true,
    target: GPTNavigationTarget = .current,
    gesture: Bool = false,
    redirect: Bool = false,
    trigger: String? = "https://muse.ai/",
    auth: Bool = false,
    recentGesture: Bool = false
) -> GPTNavigationContext {
    GPTNavigationContext(
        isTopLevel: topLevel,
        target: target,
        hasUserGesture: gesture,
        isRedirect: redirect,
        triggerURL: trigger.flatMap(URL.init(string:)),
        authenticationFlowActive: auth,
        recentUserGesture: recentGesture
    )
}

@main
private enum NavigationPolicyTestRunner {
    static func main() {
        let policy = GPTNavigationPolicy()
        let userAgentPolicy = GPTUserAgentPolicy()

expect(
    "Muse page",
    policy.decision(for: URL(string: "https://muse.ai/"), context: context()),
    .allowInApp
)
expect(
    "Muse subdomain",
    policy.decision(for: URL(string: "https://www.muse.ai/"), context: context()),
    .allowInApp
)
expect(
    "Google login from Muse",
    policy.decision(for: URL(string: "https://accounts.google.com/o/oauth2/auth"), context: context()),
    .allowInApp
)
expect(
    "OAuth provider during auth",
    policy.decision(
        for: URL(string: "https://accounts.google.com/o/oauth2/auth"),
        context: context(trigger: "https://muse.ai/", auth: true)
    ),
    .allowInApp
)
expect(
    "Apple OAuth provider during auth",
    policy.decision(
        for: URL(string: "https://appleid.apple.com/auth/authorize"),
        context: context(trigger: "https://muse.ai/", auth: true)
    ),
    .allowInApp
)
expect(
    "Cloudflare top-level challenge from Muse",
    policy.decision(
        for: URL(string: "https://challenges.cloudflare.com/turnstile/v0/"),
        context: context(redirect: true)
    ),
    .allowInApp
)
expect(
    "Auth host without Muse trigger is denied",
    policy.decision(
        for: URL(string: "https://accounts.google.com/o/oauth2/auth"),
        context: context(trigger: "https://example.org/")
    ),
    .deny
)
expect(
    "External reference click opens in app",
    policy.decision(
        for: URL(string: "https://example.org/reference"),
        context: context(gesture: true)
    ),
    .allowInApp
)
expect(
    "target blank external link opens in app",
    policy.decision(
        for: URL(string: "https://example.org/new-window"),
        context: context(target: .newWindow, gesture: true)
    ),
    .allowInApp
)
expect(
    "window.open external link opens in app",
    policy.decision(
        for: URL(string: "https://example.org/script-window"),
        context: context(target: .newWindow, gesture: false)
    ),
    .allowInApp
)
expect(
    "window.open Muse",
    policy.decision(
        for: URL(string: "https://muse.ai/"),
        context: context(target: .newWindow, gesture: true)
    ),
    .allowInApp
)
expect(
    "Subframe is unrestricted",
    policy.decision(
        for: URL(string: "https://cdn.example.net/widget"),
        context: context(topLevel: false)
    ),
    .allowInApp
)
expect(
    "Custom scheme with gesture",
    policy.decision(for: URL(string: "mailto:test@example.org"), context: context(gesture: true)),
    .openExternally
)
expect(
    "Unknown custom scheme",
    policy.decision(for: URL(string: "unsafe-scheme://payload"), context: context(gesture: true)),
    .deny
)
expect(
    "Invalid URL",
    policy.decision(for: nil, context: context()),
    .deny
)
expect(
    "Silent external redirect",
    policy.decision(
        for: URL(string: "https://malicious.example/redirect"),
        context: context(redirect: true)
    ),
    .deny
)
expect(
    "Login redirect chain through an extra host stays in app",
    policy.decision(
        for: URL(string: "https://app.anthropic.com/oauth/authorize"),
        context: context(redirect: true, trigger: "https://auth.anthropic.com/", auth: true)
    ),
    .allowInApp
)
expect(
    "Login redirect chain without auth flag is blocked",
    policy.decision(
        for: URL(string: "https://app.anthropic.com/oauth/authorize"),
        context: context(redirect: true, trigger: "https://auth.anthropic.com/", auth: false)
    ),
    .deny
)
expect(
    "Redirect right after a tap stays in app",
    policy.decision(
        for: URL(string: "https://example.org/final"),
        context: context(redirect: true, trigger: "https://example.org/", recentGesture: true)
    ),
    .allowInApp
)
expect(
    "Claude page",
    policy.decision(for: URL(string: "https://claude.ai/"), context: context()),
    .allowInApp
)
expect(
    "Claude subdomain",
    policy.decision(for: URL(string: "https://www.claude.ai/"), context: context()),
    .allowInApp
)
expect(
    "Gemini page",
    policy.decision(for: URL(string: "https://gemini.google.com/"), context: context()),
    .allowInApp
)
expect(
    "Grok page",
    policy.decision(for: URL(string: "https://grok.com/"), context: context()),
    .allowInApp
)
expect(
    "GitHub page",
    policy.decision(for: URL(string: "https://github.com/"), context: context()),
    .allowInApp
)
expect(
    "GitHub subdomain",
    policy.decision(for: URL(string: "https://gist.github.com/"), context: context()),
    .allowInApp
)
expect(
    "ChatGPT page",
    policy.decision(for: URL(string: "https://chatgpt.com/"), context: context()),
    .allowInApp
)
expect(
    "ChatGPT subdomain",
    policy.decision(for: URL(string: "https://chat.openai.com/"), context: context()),
    .allowInApp
)
expect(
    "ChatGPT login",
    policy.decision(for: URL(string: "https://auth.openai.com/"), context: context()),
    .allowInApp
)
expect(
    "Claude login",
    policy.decision(
        for: URL(string: "https://auth.anthropic.com/"),
        context: context(trigger: "https://claude.ai/")
    ),
    .allowInApp
)
expect(
    "Claude subdomain",
    policy.decision(for: URL(string: "https://support.claude.com/"), context: context()),
    .allowInApp
)
expect(
    "GitHub Pages",
    policy.decision(for: URL(string: "https://mandyims.github.io/"), context: context()),
    .allowInApp
)
expect(
    "GitHub raw file",
    policy.decision(
        for: URL(string: "https://raw.githubusercontent.com/mandyIMS/GPT-13/main/README.md"),
        context: context()
    ),
    .allowInApp
)
expect(
    "Grok login via X from Grok",
    policy.decision(
        for: URL(string: "https://x.com/i/flow/login"),
        context: context(trigger: "https://grok.com/")
    ),
    .allowInApp
)
expect(
    "X login without allowed trigger is denied",
    policy.decision(
        for: URL(string: "https://x.com/i/flow/login"),
        context: context(trigger: "https://example.org/")
    ),
    .deny
)
expect(
    "Auth host from Claude is allowed",
    policy.decision(
        for: URL(string: "https://accounts.google.com/o/oauth2/auth"),
        context: context(trigger: "https://claude.ai/")
    ),
    .allowInApp
)
expect(
    "Auth host tapped from an untrusted page stays in app",
    policy.decision(
        for: URL(string: "https://accounts.google.com/o/oauth2/auth"),
        context: context(gesture: true, trigger: "https://example.org/")
    ),
    .allowInApp
)
expect(
    "Auth host in a new window stays in app",
    policy.decision(
        for: URL(string: "https://accounts.google.com/o/oauth2/auth"),
        context: context(target: .newWindow, trigger: "https://example.org/")
    ),
    .allowInApp
)
expect(
    "Auth host hop inside a login flow stays in app",
    policy.decision(
        for: URL(string: "https://accounts.google.com/o/oauth2/auth"),
        context: context(trigger: "https://auth.anthropic.com/")
    ),
    .allowInApp
)
expect(
    "Auth host redirect after a tap stays in app",
    policy.decision(
        for: URL(string: "https://accounts.google.com/o/oauth2/auth"),
        context: context(redirect: true, trigger: "https://example.org/", recentGesture: true)
    ),
    .allowInApp
)
expect(
    "Cloudflare challenge from Gemini",
    policy.decision(
        for: URL(string: "https://challenges.cloudflare.com/turnstile/v0/"),
        context: context(redirect: true, trigger: "https://gemini.google.com/")
    ),
    .allowInApp
)
if GPTNavigationPolicy.homeURL.absoluteString != "https://muse.ai/" {
    failures.append("Selected site does not default to Muse")
}
if let customSite = GPTSiteStore.site(from: "vps.example") {
    GPTSiteStore.addCustomSite(customSite)
    expect(
        "Custom site page",
        policy.decision(for: URL(string: "https://vps.example/"), context: context()),
        .allowInApp
    )
    expect(
        "Custom site subdomain",
        policy.decision(for: URL(string: "https://chat.vps.example/"), context: context()),
        .allowInApp
    )
    GPTSiteStore.removeCustomSite(customSite)
    expect(
        "Custom site removed is denied",
        policy.decision(for: URL(string: "https://vps.example/"), context: context()),
        .deny
    )
} else {
    failures.append("Custom site parsing failed for vps.example")
}
expectUserAgentMode(
    "Google authentication compatibility UA",
    userAgentPolicy.configuration(
        for: URL(string: "https://accounts.google.com/o/oauth2/v2/auth"),
        geckoVersion: "153.0"
    ).mode,
    .googleAuthentication
)
expectUserAgentMode(
    "Muse uses the standard UA",
    userAgentPolicy.configuration(
        for: URL(string: "https://muse.ai/"),
        geckoVersion: "153.0"
    ).mode,
    .standard
)
expectUserAgentMode(
    "Apple authentication uses the standard UA",
    userAgentPolicy.configuration(
        for: URL(string: "https://appleid.apple.com/auth/authorize"),
        geckoVersion: "153.0"
    ).mode,
    .standard
)
expectUserAgentMode(
    "Lookalike Google host uses the standard UA",
    userAgentPolicy.configuration(
        for: URL(string: "https://accounts.google.com.example.org/"),
        geckoVersion: "153.0"
    ).mode,
    .standard
)

let googleConfiguration = userAgentPolicy.configuration(
    for: URL(string: "https://accounts.google.com/"),
    geckoVersion: "153.0"
)
if googleConfiguration.userAgentOverride?.contains("FxQuantum/153.0") != true {
    failures.append("Google compatibility UA does not contain the Gecko version")
}
if googleConfiguration.userAgentOverride?.contains("Chrome/157.0.0.0") != true {
    failures.append("Google compatibility UA does not contain the derived Chrome version")
}

let standardConfiguration = userAgentPolicy.configuration(
    for: URL(string: "https://muse.ai/"),
    geckoVersion: "153.0"
)
if standardConfiguration.userAgentOverride
    != "Mozilla/5.0 (Android 15; Mobile; rv:153.0) Gecko/153.0 Firefox/153.0" {
    failures.append("Standard UA does not match Reynard's Android Firefox identity")
}
if standardConfiguration.platformOverride != "Linux armv81"
    || standardConfiguration.appVersionOverride != "5.0 (Android 15)"
    || standardConfiguration.oscpuOverride != "Linux armv81" {
    failures.append("Standard navigator overrides do not match Reynard")
}

let gitHubConfiguration = userAgentPolicy.configuration(
    for: URL(string: "https://github.com/"),
    geckoVersion: "153.0"
)
if gitHubConfiguration.userAgentOverride?.contains("Safari/604.1") != true
    || gitHubConfiguration.platformOverride != "iPhone"
    || gitHubConfiguration.oscpuOverride != "iPhone OS 16_1_2" {
    failures.append("GitHub UA does not identify as Safari on iPhone")
}

let gitHubSubdomainConfiguration = userAgentPolicy.configuration(
    for: URL(string: "https://gist.github.com/"),
    geckoVersion: "153.0"
)
if gitHubSubdomainConfiguration.userAgentOverride?.contains("Safari/604.1") != true {
    failures.append("GitHub subdomain UA does not identify as Safari on iPhone")
}

let lookalikeGitHubConfiguration = userAgentPolicy.configuration(
    for: URL(string: "https://github.com.example.org/"),
    geckoVersion: "153.0"
)
if lookalikeGitHubConfiguration.userAgentOverride?.contains("Safari/604.1") == true {
    failures.append("Lookalike GitHub host must not use the Safari UA")
}

if GPTDeepLink.site(for: URL(string: "muse13v3://muse.ai")!)?.name != "Muse" {
    failures.append("Deep link to Muse does not resolve to the Muse site")
}
if GPTDeepLink.site(for: URL(string: "muse13v3://claude.ai")!)?.name != "Claude" {
    failures.append("Deep link to Claude does not resolve to the Claude site")
}
if GPTDeepLink.site(for: URL(string: "muse13v3://gemini.google.com")!)?.name != "Gemini" {
    failures.append("Deep link to Gemini does not resolve to the Gemini site")
}
if GPTDeepLink.site(for: URL(string: "muse13v3://www.chatgpt.com")!)?.name != "ChatGPT" {
    failures.append("Deep link with a www. prefix does not resolve to the ChatGPT site")
}
if GPTDeepLink.site(for: URL(string: "muse13v3://example.com")!) != nil {
    failures.append("Deep link to an unknown host should be ignored")
}
if GPTDeepLink.site(for: URL(string: "https://claude.ai/")!) != nil {
    failures.append("An https URL is not a deep link")
}
if GPTSiteStore.defaultSite(forDefaultURLString: "https://claude.ai/")?.name != "Claude" {
    failures.append("Baked-in default site does not resolve to the Claude site")
}
if GPTSiteStore.defaultSite(forDefaultURLString: "https://chatgpt.com/chat")?.name != "ChatGPT" {
    failures.append("Baked-in default site does not match by host")
}
if GPTSiteStore.defaultSite(forDefaultURLString: "https://example.com/") != nil {
    failures.append("Baked-in default site for an unknown host should be ignored")
}
if GPTSiteStore.defaultSite(forDefaultURLString: nil) != nil
    || GPTSiteStore.defaultSite(forDefaultURLString: "not a url") != nil {
    failures.append("Baked-in default site should ignore missing or bad values")
}

        if failures.isEmpty {
            print("ReynardGPT navigation and user-agent policies: 66 tests passed")
        } else {
            failures.forEach { fputs("FAIL: \($0)\n", stderr) }
            exit(1)
        }
    }
}
