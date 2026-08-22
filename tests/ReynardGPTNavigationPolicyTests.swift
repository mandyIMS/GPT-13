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
    trigger: String? = "https://chatgpt.com/",
    auth: Bool = false
) -> GPTNavigationContext {
    GPTNavigationContext(
        isTopLevel: topLevel,
        target: target,
        hasUserGesture: gesture,
        isRedirect: redirect,
        triggerURL: trigger.flatMap(URL.init(string:)),
        authenticationFlowActive: auth
    )
}

@main
private enum NavigationPolicyTestRunner {
    static func main() {
        let policy = GPTNavigationPolicy()
        let userAgentPolicy = GPTUserAgentPolicy()

expect(
    "ChatGPT page",
    policy.decision(for: URL(string: "https://chatgpt.com/c/123"), context: context()),
    .allowInApp
)
expect(
    "ChatGPT subdomain",
    policy.decision(for: URL(string: "https://help.chatgpt.com/article"), context: context()),
    .allowInApp
)
expect(
    "OpenAI login",
    policy.decision(for: URL(string: "https://auth.openai.com/authorize"), context: context()),
    .allowInApp
)
expect(
    "OAuth provider during auth",
    policy.decision(
        for: URL(string: "https://accounts.google.com/o/oauth2/auth"),
        context: context(trigger: "https://auth.openai.com/authorize", auth: true)
    ),
    .allowInApp
)
expect(
    "Apple OAuth provider during auth",
    policy.decision(
        for: URL(string: "https://appleid.apple.com/auth/authorize"),
        context: context(trigger: "https://auth.openai.com/authorize", auth: true)
    ),
    .allowInApp
)
expect(
    "Cloudflare top-level challenge from ChatGPT",
    policy.decision(
        for: URL(string: "https://challenges.cloudflare.com/turnstile/v0/"),
        context: context(redirect: true)
    ),
    .allowInApp
)
expect(
    "ChatGPT signed download host",
    policy.decision(
        for: URL(string: "https://files.oaiusercontent.com/file-download"),
        context: context(redirect: true)
    ),
    .allowInApp
)
expect(
    "External reference click",
    policy.decision(
        for: URL(string: "https://example.org/reference"),
        context: context(gesture: true)
    ),
    .openExternally
)
expect(
    "target blank external link",
    policy.decision(
        for: URL(string: "https://example.org/new-window"),
        context: context(target: .newWindow, gesture: true)
    ),
    .openExternally
)
expect(
    "window.open external link",
    policy.decision(
        for: URL(string: "https://example.org/script-window"),
        context: context(target: .newWindow, gesture: false)
    ),
    .openExternally
)
expect(
    "window.open ChatGPT",
    policy.decision(
        for: URL(string: "https://chatgpt.com/share/123"),
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
expectUserAgentMode(
    "Google authentication compatibility UA",
    userAgentPolicy.configuration(
        for: URL(string: "https://accounts.google.com/o/oauth2/v2/auth"),
        geckoVersion: "153.0"
    ).mode,
    .googleAuthentication
)
expectUserAgentMode(
    "ChatGPT uses the standard UA",
    userAgentPolicy.configuration(
        for: URL(string: "https://chatgpt.com/"),
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
    for: URL(string: "https://chatgpt.com/"),
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

        if failures.isEmpty {
            print("ReynardGPT navigation and user-agent policies: 24 tests passed")
        } else {
            failures.forEach { fputs("FAIL: \($0)\n", stderr) }
            exit(1)
        }
    }
}
