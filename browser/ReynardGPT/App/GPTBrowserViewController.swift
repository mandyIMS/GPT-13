import Darwin
import GeckoView
import UIKit

private func makeWebsiteModeSetting(
    for configuration: GPTUserAgentConfiguration
) -> WebsiteModeSetting {
    WebsiteModeSetting(
        userAgentOverride: configuration.userAgentOverride,
        platformOverride: configuration.platformOverride,
        appVersionOverride: configuration.appVersionOverride,
        oscpuOverride: configuration.oscpuOverride,
        buildIDOverride: configuration.buildIDOverride,
        userAgentMode: 0,
        viewportMode: 0
    )
}

private func makeReynardGPTInitialSession() -> GeckoSession {
    let configuration = GPTUserAgentPolicy().configuration(
        for: GPTNavigationPolicy.homeURL,
        geckoVersion: GeckoRuntime.version
    )
    return GeckoSession(
        settings: GeckoSessionSettings(
            websiteMode: makeWebsiteModeSetting(for: configuration),
            pageZoom: .default,
            language: LanguageSetting(codes: ["zh-CN", "zh", "en"])
        )
    )
}

@MainActor
final class GPTBrowserViewController: UIViewController {
    private let geckoView = GeckoView()
    private let toolbar = UIToolbar()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let policy = GPTNavigationPolicy()
    private let userAgentPolicy = GPTUserAgentPolicy()
    private let selectionController = GPTSelectionController()
    private let session = makeReynardGPTInitialSession()
    private let downloadStore = GPTDownloadStore.shared
    private var geckoTopConstraint: NSLayoutConstraint?
    private var geckoBottomConstraint: NSLayoutConstraint?
    private var focusedInputOffset: CGFloat = 0
    private var filePicker: GPTFilePicker?
    private var authenticationFlowActive = false
    /// When the user last tapped something. A redirect that follows a tap
    /// within a few seconds is part of that tap, so the policy lets it
    /// stay in the app instead of blocking it as a silent redirect.
    private var lastUserGestureDate: Date?
    private var activeUserAgentConfiguration = GPTUserAgentPolicy().configuration(
        for: GPTNavigationPolicy.homeURL,
        geckoVersion: GeckoRuntime.version
    )
    private var currentURL = GPTNavigationPolicy.homeURL
    /// Deep link the app was launched with, if any. Applied once as the
    /// initial page instead of the selected site.
    var launchDeepLinkURL: URL?
    private var lastExternalOpen: (url: URL, date: Date)?
    private var lastNewWindowLoad: (url: URL, date: Date)?
    /// Background sessions handed to the engine for new-window requests.
    /// They keep the engine from handing the URL to the system browser;
    /// the page itself is shown in the current tab instead. Closed after
    /// a delay so they do not pile up.
    private var popupSessions: [GeckoSession] = []
    /// A login popup currently shown in place of the main tab. Google
    /// and similar logins open a real popup window and expect it to talk
    /// back to the page that opened it (window.opener); stuffing the
    /// popup's page into the main tab leaves no opener, so the login
    /// stalls on a blank page. A login popup is therefore shown as its
    /// own temporary tab, and the main tab is restored when it closes
    /// or finishes.
    private var displayedPopupSession: GeckoSession?
    /// The main tab's URL before a login popup was shown, restored when
    /// the popup goes away so the tab keeps tracking the page it was on.
    private var mainSessionURLBeforePopup: URL?

    private lazy var backItem = UIBarButtonItem(
        image: UIImage(systemName: "chevron.backward"),
        style: .plain,
        target: self,
        action: #selector(goBack)
    )

    private lazy var downloadsItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.down.circle"),
        style: .plain,
        target: self,
        action: #selector(showDownloads)
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        GPTWebsiteDataClearDiagnostics.markInterruptedAttemptIfNeeded()
        view.backgroundColor = .systemBackground
        configureLayout()
        configureToolbar()
        configureSession()
        observeKeyboard()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadsDidChange),
            name: .gptDownloadsDidChange,
            object: downloadStore
        )
        updateDownloadsItem()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        session.close()
    }

    private func configureLayout() {
        geckoView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(geckoView)
        view.addSubview(toolbar)
        view.addSubview(progressView)

        let geckoTopConstraint = geckoView.topAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.topAnchor
        )
        let geckoBottomConstraint = geckoView.bottomAnchor.constraint(equalTo: toolbar.topAnchor)
        self.geckoTopConstraint = geckoTopConstraint
        self.geckoBottomConstraint = geckoBottomConstraint

        NSLayoutConstraint.activate([
            geckoTopConstraint,
            geckoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            geckoBottomConstraint,
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard view.window != nil,
              focusedInputOffset == 0,
              let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }

        let keyboardFrame = view.convert(frameValue.cgRectValue, from: nil)
        let isDockedAtBottom = keyboardFrame.maxY >= view.bounds.maxY - 1
            && keyboardFrame.width >= view.bounds.width * 0.8
        guard isDockedAtBottom, !session.isInHardwareKeyboardMode() else {
            resetFocusedInputRelocation(using: notification)
            return
        }

        relocateFocusedInput(above: keyboardFrame, using: notification)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        resetFocusedInputRelocation(using: notification)
    }

    private func relocateFocusedInput(above keyboardFrame: CGRect, using notification: Notification) {
        view.layoutIfNeeded()
        let unshiftedFrame = geckoView.frame.offsetBy(dx: 0, dy: focusedInputOffset)
        let newOffset = max(0, unshiftedFrame.maxY - keyboardFrame.minY)
        guard abs(newOffset - focusedInputOffset) > 1 else { return }

        focusedInputOffset = newOffset
        updateFocusedInputConstraints()
        animateKeyboardLayout(keyboardAnimation(from: notification))
    }

    private func resetFocusedInputRelocation(using notification: Notification) {
        guard focusedInputOffset != 0 else { return }
        focusedInputOffset = 0
        updateFocusedInputConstraints()
        animateKeyboardLayout(keyboardAnimation(from: notification))
    }

    private func updateFocusedInputConstraints() {
        // Change both constants by the same amount. This translates Gecko's
        // surface without changing its size, keeping IME and touch coordinates stable.
        geckoTopConstraint?.constant = -focusedInputOffset
        geckoBottomConstraint?.constant = -focusedInputOffset
    }

    private func keyboardAnimation(from notification: Notification) -> (TimeInterval, UIView.AnimationOptions) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
            as? TimeInterval ?? 0.25
        let rawCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey]
            as? UInt ?? 7
        return (duration, UIView.AnimationOptions(rawValue: rawCurve << 16))
    }

    private func animateKeyboardLayout(_ animation: (TimeInterval, UIView.AnimationOptions)) {
        UIView.animate(
            withDuration: animation.0,
            delay: 0,
            options: [animation.1, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.view.layoutIfNeeded()
        }
    }

    private func configureToolbar() {
        backItem.isEnabled = false
        let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let reload = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(reloadPage)
        )
        let settings = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(showSettings)
        )
        toolbar.items = [backItem, flexible, reload, flexible, downloadsItem, flexible, settings]
    }

    private func configureSession() {
        session.navigationDelegate = self
        session.progressDelegate = self
        session.contentDelegate = self
        session.permissionDelegate = self
        session.promptDelegate = self
        session.selectionActionDelegate = selectionController
        session.open()
        geckoView.session = session
        if let launchURL = launchDeepLinkURL,
           let site = GPTDeepLink.site(for: launchURL) {
            GPTSiteStore.select(site)
        }
        let initialURL = ProcessInfo.processInfo.environment["REYNARD_UI_TEST_URL"]
            ?? GPTNavigationPolicy.homeURL.absoluteString
        if let url = URL(string: initialURL) {
            currentURL = url
        }
        session.load(initialURL)
    }

    @objc private func goBack() {
        (displayedPopupSession ?? session).goBack()
    }

    @objc private func reloadPage() {
        (displayedPopupSession ?? session).reload()
    }

    @objc private func showDownloads() {
        let downloads = GPTDownloadsViewController(store: downloadStore)
        let navigation = UINavigationController(rootViewController: downloads)
        present(navigation, animated: true)
    }

    @objc private func downloadsDidChange() {
        updateDownloadsItem()
    }

    private func updateDownloadsItem() {
        let summary = downloadStore.summary()
        let highlighted = summary.activeCount > 0 || summary.hasUnviewedCompletedDownloads
        downloadsItem.image = UIImage(
            systemName: highlighted ? "arrow.down.circle.fill" : "arrow.down.circle"
        )
        downloadsItem.accessibilityLabel = "下载"
        downloadsItem.accessibilityValue = summary.activeCount > 0
            ? "\(summary.activeCount) 个下载进行中"
            : "\(summary.items.count) 个下载"
    }

    @objc private func showSettings() {
        let settings = GPTSettingsViewController(
            clearWebsiteData: {
                GPTWebsiteDataCleaner.scheduleProfileReset()
            },
            didClearWebsiteData: { [weak self] in
                self?.session.stop()
                // The pending reset runs at the very beginning of the next
                // launch, before Gecko opens its profile.
                exit(EXIT_SUCCESS)
            },
            onSiteSelected: { [weak self] url in
                self?.switchToSite(url)
            }
        )
        let navigation = UINavigationController(rootViewController: settings)
        present(navigation, animated: true)
    }

    private func switchToSite(_ url: URL) {
        authenticationFlowActive = false
        currentURL = url
        updateUserAgent(for: url)
        session.load(url.absoluteString)
    }

    /// Opens a `muse13v3://<host>` deep link from a Home Screen shortcut.
    /// Unknown hosts are ignored. When the view has not loaded yet, the
    /// link is kept and applied as the initial page instead.
    func openDeepLink(_ url: URL) {
        guard let site = GPTDeepLink.site(for: url) else { return }
        guard isViewLoaded else {
            launchDeepLinkURL = url
            return
        }
        GPTSiteStore.select(site)
        switchToSite(site.url)
    }

    private func navigationContext(
        for request: LoadRequest,
        topLevel: Bool = true
    ) -> GPTNavigationContext {
        let hasGesture = request.hasUserGesture || request.isUserInitiatedNavigation
        if hasGesture {
            lastUserGestureDate = Date()
        }
        let recentUserGesture = lastUserGestureDate.map {
            Date().timeIntervalSince($0) < 5
        } ?? false
        return GPTNavigationContext(
            isTopLevel: topLevel,
            target: request.target == .current ? .current : .newWindow,
            hasUserGesture: hasGesture,
            isRedirect: request.isRedirect,
            // Redirects sometimes carry no trigger URL; the page the user
            // is actually on is the honest "from" site (login redirects
            // to an auth host would otherwise be denied as coming from
            // nowhere and show a blank page).
            triggerURL: request.triggerUri.flatMap(URL.init(string:)) ?? currentURL,
            authenticationFlowActive: authenticationFlowActive,
            recentUserGesture: recentUserGesture
        )
    }

    private func evaluate(
        url: URL?,
        context: GPTNavigationContext,
        openExternal: Bool
    ) -> AllowOrDeny {
        switch policy.decision(for: url, context: context) {
        case .allowInApp:
            updateUserAgent(for: url)
            if policy.beginsAuthenticationFlow(url) {
                authenticationFlowActive = true
            }
            return .allow
        case .openExternally:
            if openExternal, let url {
                openInDefaultBrowserOnce(url)
            }
            return .deny
        case .deny:
            return .deny
        }
    }

    private func updateUserAgent(for url: URL?) {
        let configuration = userAgentPolicy.configuration(
            for: url,
            geckoVersion: GeckoRuntime.version
        )
        guard configuration != activeUserAgentConfiguration else { return }
        activeUserAgentConfiguration = configuration

        let currentSettings = session.settings
        session.updateSettings(
            GeckoSessionSettings(
                websiteMode: makeWebsiteModeSetting(for: configuration),
                pageZoom: currentSettings.pageZoom,
                language: currentSettings.language
            )
        )
    }

    private func openInDefaultBrowserOnce(_ url: URL) {
        if let lastExternalOpen,
           lastExternalOpen.url == url,
           Date().timeIntervalSince(lastExternalOpen.date) < 1 {
            return
        }
        lastExternalOpen = (url, Date())
        UIApplication.shared.open(url, options: [:])
    }

    /// Handles a link that asks for a new window (for example a link in the
    /// chat that opens with target _blank). New-window requests must be
    /// handled by the app itself: letting Gecko continue one on its own can
    /// hand the URL to the system browser, even for a whitelisted site.
    /// Returning .deny tells Gecko the request is fully handled.
    private func handleNewWindow(
        url: URL?,
        context: GPTNavigationContext
    ) -> AllowOrDeny {
        switch policy.decision(for: url, context: context) {
        case .allowInApp:
            updateUserAgent(for: url)
            if policy.beginsAuthenticationFlow(url) {
                authenticationFlowActive = true
            }
            loadNewWindowURLOnce(url)
            return .deny
        case .openExternally:
            if let url {
                openInDefaultBrowserOnce(url)
            }
            return .deny
        case .deny:
            return .deny
        }
    }

    /// Loads a new-window URL in the current tab, once per URL per second.
    /// The load is deferred to the next run-loop turn so it is not cancelled
    /// together with the popup request that asked for the new window.
    private func loadNewWindowURLOnce(_ url: URL?) {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }
        if let lastNewWindowLoad,
           lastNewWindowLoad.url == url,
           Date().timeIntervalSince(lastNewWindowLoad.date) < 1 {
            return
        }
        lastNewWindowLoad = (url, Date())
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // A new-window page goes to the tab on screen: the main
            // tab, or a login popup shown in its place.
            (self.displayedPopupSession ?? self.session).load(url.absoluteString)
        }
    }

    /// Whether this session is the login popup currently on screen.
    private func isDisplayedPopup(_ s: GeckoSession) -> Bool {
        displayedPopupSession.map { s === $0 } ?? false
    }

    /// Shows a login popup as its own temporary tab and remembers the
    /// main tab's URL so it can be restored when the popup goes away.
    private func showLoginPopup(_ popup: GeckoSession) {
        mainSessionURLBeforePopup = currentURL
        displayedPopupSession = popup
        geckoView.session = popup
    }

    /// Puts the main tab back on screen when a login popup goes away
    /// and closes the popup session. The main tab's page is left alone
    /// so a login it is finishing (it just heard back from the popup)
    /// is not interrupted.
    private func hideLoginPopup() {
        guard let popup = displayedPopupSession else { return }
        displayedPopupSession = nil
        if let mainURL = mainSessionURLBeforePopup {
            currentURL = mainURL
            mainSessionURLBeforePopup = nil
        }
        geckoView.session = session
        popup.close()
        popupSessions.removeAll { $0 === popup }
    }

    private func confirm(title: String, message: String?) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Don’t Allow", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                continuation.resume(returning: true)
            })
            present(alert, animated: true)
        }
    }
}

extension GPTBrowserViewController: NavigationDelegate {
    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {
        guard session === self.session || isDisplayedPopup(session) else { return }
        guard let url = url.flatMap(URL.init(string:)) else { return }
        currentURL = url
        // The user-agent configuration belongs to the main tab's page;
        // a login popup keeps the settings it was created with, so a
        // popup navigation must not reconfigure the main tab (which is
        // waiting, as the opener, for the login to report back).
        if !isDisplayedPopup(session) {
            updateUserAgent(for: url)
        }
        let wasAuthActive = authenticationFlowActive
        if policy.completesAuthenticationFlow(url) {
            authenticationFlowActive = false
            // The login popup reached the site itself: the login
            // finished. Put the main tab back and take it to the
            // site's home page, where the login cookie signs the user
            // in. A callback page (carrying a code) is left alone
            // until it moves on or the stuck-callback recovery below
            // rescues it.
            if isDisplayedPopup(session), !isOAuthCallback(url) {
                hideLoginPopup()
                self.session.load(GPTNavigationPolicy.homeURL.absoluteString)
                return
            }
        }
        // A callback page (carrying the login's code) that is still
        // the visible page a few seconds later is stuck; rescue it.
        // This covers callbacks on a login host and callbacks that
        // landed back on the site itself.
        if isOAuthCallback(url),
           policy.beginsAuthenticationFlow(url) || policy.completesAuthenticationFlow(url),
           wasAuthActive || isDisplayedPopup(session) {
            recoverStuckOAuthCallback(url)
        }
    }

    func onCanGoBack(session: GeckoSession, canGoBack: Bool) {
        guard session === self.session || isDisplayedPopup(session) else { return }
        backItem.isEnabled = canGoBack
    }

    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        if session !== self.session {
            // A login popup shown on screen loads its own pages in
            // place, so its login can talk back to the main tab that
            // opened it. Other background popups are still routed to
            // the visible tab.
            if isDisplayedPopup(session) {
                return decidePopupRequest(request)
            }
            return routePopupRequest(request)
        }
        let url = URL(string: request.uri)
        let context = navigationContext(for: request)
        if context.target == .newWindow {
            return handleNewWindow(url: url, context: context)
        }
        return evaluate(
            url: url,
            context: context,
            openExternal: true
        )
    }

    func onPreNavigation(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        if session !== self.session {
            if isDisplayedPopup(session) {
                return decidePopupRequest(request)
            }
            return routePopupRequest(request)
        }
        let url = URL(string: request.uri)
        let context = navigationContext(for: request)
        if context.target == .newWindow {
            return handleNewWindow(url: url, context: context)
        }
        return evaluate(
            url: url,
            context: context,
            openExternal: true
        )
    }

    func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny {
        .allow
    }

    func onNewSession(
        session: GeckoSession,
        uri: String,
        windowId: String,
        target: LoadRequestTarget
    ) async -> GeckoSession? {
        let context = GPTNavigationContext(
            isTopLevel: true,
            target: .newWindow,
            hasUserGesture: true,
            isRedirect: false,
            triggerURL: currentURL,
            authenticationFlowActive: authenticationFlowActive,
            recentUserGesture: true
        )
        let url = URL(string: uri)
        switch policy.decision(for: url, context: context) {
        case .allowInApp:
            if policy.beginsAuthenticationFlow(url) {
                authenticationFlowActive = true
            } else {
                updateUserAgent(for: url)
            }
            // The engine needs a real session for a new window. Returning
            // nil made it hand the URL to the system browser, even for a
            // whitelisted site. Hand it a background session (its
            // navigations are routed to the visible tab by
            // routePopupRequest, so popup logins and links are visible
            // and usable) and show the page in the current tab instead.
            // A login popup is different: the login expects a real
            // popup window that talks back to the page that opened it,
            // so it is shown as its own temporary tab instead, and the
            // main tab is restored when it closes or finishes.
            let popup = makeReynardGPTInitialSession()
            popup.navigationDelegate = self
            popup.progressDelegate = self
            popup.contentDelegate = self
            // A session that was never opened has no engine window, and
            // GeckoSessionHandler drops every event from it (it guards
            // on isOpen()), so the popup's navigations never reach
            // routePopupRequest: the engine falls back to handing the
            // URL to Safari, and popup logins (Claude) stay blank.
            // That is why v3 still failed although this code was in
            // the build. Open it with the window ID the engine gave
            // us, the way upstream opens every session that does
            // real work (SessionManager, AddonPopup, LinkPreview).
            popup.open(windowId: windowId)
            popupSessions.append(popup)
            if policy.beginsAuthenticationFlow(url), displayedPopupSession == nil {
                showLoginPopup(popup)
            } else {
                // A login popup is already on screen (or this is not a
                // login): the page goes to the tab on screen, which is
                // the popup already showing if there is one.
                loadNewWindowURLOnce(url)
            }
            closePopupSessionAfterDelay(popup)
            return popup
        case .openExternally:
            if let url { openInDefaultBrowserOnce(url) }
            return nil
        case .deny:
            return nil
        }
    }

    private func closePopupSessionAfterDelay(_ popup: GeckoSession, attemptsLeft: Int = 9) {
        // DispatchQueue.asyncAfter, not Task.sleep(for:), because the
        // Duration-based sleep needs iOS 16 and this app targets iOS 13.
        // A login routinely takes longer than 30 seconds (pick an
        // account, type a password, answer a verification), and closing
        // the popup session mid-login cuts the flow off, so while a
        // login is in progress the close waits and checks again. After
        // about five minutes the login is abandoned and the session is
        // closed anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if let self, self.isDisplayedPopup(popup) {
                // A login popup on screen is not closed while the user
                // is still working in it. Past the wait it is put away
                // first (the main tab comes back) so the screen does
                // not go blank, and then it is closed.
                if self.authenticationFlowActive, attemptsLeft > 0 {
                    self.closePopupSessionAfterDelay(popup, attemptsLeft: attemptsLeft - 1)
                    return
                }
                self.hideLoginPopup()
                return
            }
            if let self, self.authenticationFlowActive, attemptsLeft > 0 {
                self.closePopupSessionAfterDelay(popup, attemptsLeft: attemptsLeft - 1)
                return
            }
            popup.close()
            self?.popupSessions.removeAll { $0 === popup }
        }
    }

    /// An OAuth callback page (a login host URL carrying the `code` the
    /// login issued) is expected to send the user onward within a
    /// moment, either by redirecting or by closing itself. If it is
    /// still the visible page a few seconds later, it is stuck: the tab
    /// sits on a blank callback page and the login never finishes.
    /// Take the tab to the site's home page instead, where the login
    /// cookie the callback set signs the user in. A page that moves on
    /// by itself, or a login that already finished, is left alone.
    private func recoverStuckOAuthCallback(_ callbackURL: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self,
                  self.authenticationFlowActive || self.displayedPopupSession != nil,
                  self.currentURL == callbackURL else { return }
            self.authenticationFlowActive = false
            // If the stuck page is a login popup on screen, put the
            // main tab back first so the rescue is visible.
            if self.displayedPopupSession != nil {
                self.hideLoginPopup()
            }
            self.session.load(GPTNavigationPolicy.homeURL.absoluteString)
        }
    }

    private func isOAuthCallback(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return false }
        return items.contains { $0.name == "code" || $0.name == "state" }
    }

    /// Decides a navigation inside the login popup shown on screen.
    /// Unlike a background popup, it loads in place (allow) so the
    /// login keeps its window and opener; it never touches the main
    /// tab's user-agent configuration.
    private func decidePopupRequest(_ request: LoadRequest) -> AllowOrDeny {
        let url = URL(string: request.uri)
        let context = navigationContext(for: request)
        switch policy.decision(for: url, context: context) {
        case .allowInApp:
            if policy.beginsAuthenticationFlow(url) {
                authenticationFlowActive = true
            }
            return .allow
        case .openExternally:
            if let url {
                openInDefaultBrowserOnce(url)
            }
            return .deny
        case .deny:
            return .deny
        }
    }

    /// A navigation inside a background (popup) session: show it in the
    /// visible tab instead, so popup logins and popup links are visible
    /// and usable rather than loading in an invisible session (which
    /// looks like a blank page). Always denied in the popup itself.
    private func routePopupRequest(_ request: LoadRequest) -> AllowOrDeny {
        let url = URL(string: request.uri)
        let context = navigationContext(for: request)
        guard context.isTopLevel,
              let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .deny
        }
        switch policy.decision(for: url, context: context) {
        case .allowInApp:
            updateUserAgent(for: url)
            if policy.beginsAuthenticationFlow(url) {
                authenticationFlowActive = true
            }
            loadNewWindowURLOnce(url)
            return .deny
        case .openExternally:
            openInDefaultBrowserOnce(url)
            return .deny
        case .deny:
            return .deny
        }
    }
}

extension GPTBrowserViewController: ProgressDelegate {
    func onPageStart(session: GeckoSession, url: String) {
        guard session === self.session || isDisplayedPopup(session) else { return }
        progressView.isHidden = false
        progressView.progress = 0.05
    }

    func onProgressChange(session: GeckoSession, progress: Int) {
        guard session === self.session || isDisplayedPopup(session) else { return }
        progressView.setProgress(Float(progress) / 100, animated: true)
    }

    func onPageStop(session: GeckoSession, success: Bool) {
        guard session === self.session || isDisplayedPopup(session) else { return }
        progressView.setProgress(1, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.progressView.isHidden = true
            self?.progressView.progress = 0
        }
    }
}

extension GPTBrowserViewController: PermissionEmbedderDelegate {
    func permissionDelegate(
        decideContentPermission permission: ContentPermission,
        session: GeckoSession
    ) async -> ContentPermission.Value {
        guard let requestedPermission = permission.permission else { return .deny }
        switch requestedPermission {
        case .persistentStorage, .storageAccess, .autoplay:
            return .allow
        case .camera, .microphone, .geolocation:
            let host = ContentPermission.permissionHost(from: permission.uri)
            if let allowed = GPTSitePermissionStore.decision(
                for: requestedPermission,
                host: host
            ) {
                let value: ContentPermission.Value = allowed ? .allow : .deny
                PermissionDelegate.setPermission(permission, value: value)
                return value
            }
            let allowed = await confirm(
                title: "Allow \(host)?",
                message: "This permission is required by the current Muse page."
            )
            GPTSitePermissionStore.setDecision(allowed, for: requestedPermission, host: host)
            let value: ContentPermission.Value = allowed ? .allow : .deny
            PermissionDelegate.setPermission(permission, value: value)
            return value
        default:
            return .deny
        }
    }

    func permissionDelegate(
        decideMediaPermission request: MediaPermissionRequest,
        session: GeckoSession
    ) async -> Bool {
        var requested: [ContentPermission.Permission] = []
        if request.videoRequested { requested.append(.camera) }
        if request.audioRequested { requested.append(.microphone) }
        guard !requested.isEmpty else { return false }

        let decisions = requested.map { GPTSitePermissionStore.decision(for: $0, host: request.host) }
        if decisions.contains(where: { $0 == false }) { return false }
        if decisions.allSatisfy({ $0 == true }) { return true }

        let capabilities: String
        switch (request.videoRequested, request.audioRequested) {
        case (true, true): capabilities = "camera and microphone"
        case (true, false): capabilities = "camera"
        case (false, true): capabilities = "microphone"
        case (false, false): return false
        }
        let allowed = await confirm(
            title: "Allow \(request.host) to use the \(capabilities)?",
            message: "iOS may show an additional system permission prompt."
        )
        for permission in requested {
            GPTSitePermissionStore.setDecision(allowed, for: permission, host: request.host)
        }
        return allowed
    }
}

extension GPTBrowserViewController: ContentDelegate {
    func onCloseRequest(session: GeckoSession) {
        // An OAuth callback page is written to close its own popup
        // window once the login is done (it hands the code to its
        // opener and calls window.close()). When that page ends up in
        // the visible tab — the app routes popup pages there — there is
        // no opener and no popup to close, so the tab just sits on the
        // callback page, which renders blank. Treat the close request
        // as "login finished": take the visible tab back to the site's
        // home page, where the login cookie the callback set puts the
        // user straight into the site. A close request from a
        // background popup session just closes that popup. A close
        // request outside a login is ignored.
        if session === self.session {
            guard authenticationFlowActive || policy.beginsAuthenticationFlow(currentURL) else { return }
            authenticationFlowActive = false
            session.load(GPTNavigationPolicy.homeURL.absoluteString)
            return
        }
        if isDisplayedPopup(session) {
            // The login popup closed itself: its login finished and it
            // handed the result back to the main tab. Put the main tab
            // back on screen and let it finish signing in; its page
            // is left alone so the login it is finishing is not cut off.
            hideLoginPopup()
            return
        }
        session.close()
        popupSessions.removeAll { $0 === session }
    }

    func onSlowScript(session: GeckoSession, scriptFileName: String) async -> SlowScriptResponse {
        .resume
    }

    func onCrash(session: GeckoSession) {
        if session !== self.session, !isDisplayedPopup(session) {
            // A background popup crashed; drop it without touching
            // the screen.
            session.close()
            popupSessions.removeAll { $0 === session }
            return
        }
        session.close()
        session.open()
        geckoView.session = session
        session.load(currentURL.absoluteString)
    }

    func onExternalResponse(session: GeckoSession, response: ExternalResponseInfo) async -> Bool {
        let accepted = await confirm(
            title: "Download \(response.filename ?? "file")?",
            message: response.mimeType
        )
        guard accepted else { return false }
        return downloadStore.begin(response)
    }

    func onExternalResponseProgress(
        session: GeckoSession,
        localFilePath: String,
        bytesReceived: Int64
    ) -> Bool {
        downloadStore.update(localFilePath: localFilePath, bytesReceived: bytesReceived)
    }

    func onExternalResponseComplete(session: GeckoSession, localFilePath: String, succeeded: Bool) {
        downloadStore.complete(localFilePath: localFilePath, succeeded: succeeded)
    }
}

extension GPTBrowserViewController: PromptDelegate {
    func onPrompt(session: GeckoSession, request: PromptRequest) async -> PromptResponse? {
        switch request {
        case .alert(let request):
            _ = await confirm(title: request.title, message: request.message)
            return .button(0)
        case .button(let request):
            return await presentButtonPrompt(request)
        case .text(let request):
            return await presentTextPrompt(request)
        case .auth(let request):
            return await presentAuthPrompt(request)
        case .folderUpload:
            return .folderUpload(allowed: await confirm(
                title: "Upload this folder?",
                message: "The selected folder contents will be shared with Muse."
            ))
        case .color(let request):
            return .color(request.value)
        case .dateTime(let request):
            return .dateTime(request.value)
        case .file(let request):
            let picker = GPTFilePicker()
            filePicker = picker
            let result = await picker.present(request: request, from: self)
            filePicker = nil
            return result.map(PromptResponse.files)
        case .choice(let request):
            return await presentChoicePrompt(request)
        case .share(let request):
            var items: [Any] = []
            if !request.text.isEmpty { items.append(request.text) }
            if let url = request.url.flatMap(URL.init(string:)) { items.append(url) }
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            present(activity, animated: true)
            return .share(.success)
        }
    }

    func onPromptDismiss(session: GeckoSession, promptId: String) {
        filePicker?.cancel()
        filePicker = nil
        presentedViewController?.dismiss(animated: false)
    }

    private func presentButtonPrompt(_ request: ButtonPromptRequest) async -> PromptResponse? {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: request.title, message: request.message, preferredStyle: .alert)
            let titles = request.buttonTitles + request.customButtonTitles
            for (index, title) in titles.enumerated() {
                alert.addAction(UIAlertAction(title: title, style: index == 1 ? .cancel : .default) { _ in
                    continuation.resume(returning: .button(index))
                })
            }
            if titles.isEmpty {
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    continuation.resume(returning: .button(0))
                })
            }
            present(alert, animated: true)
        }
    }

    private func presentTextPrompt(_ request: TextPromptRequest) async -> PromptResponse? {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: request.title, message: request.message, preferredStyle: .alert)
            alert.addTextField { $0.text = request.value }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume(returning: .text(alert.textFields?.first?.text ?? ""))
            })
            present(alert, animated: true)
        }
    }

    private func presentAuthPrompt(_ request: AuthPromptRequest) async -> PromptResponse? {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: request.title, message: request.message, preferredStyle: .alert)
            alert.addTextField {
                $0.placeholder = "Username"
                $0.text = request.username
                $0.textContentType = .username
            }
            alert.addTextField {
                $0.placeholder = "Password"
                $0.text = request.password
                $0.isSecureTextEntry = true
                $0.textContentType = .password
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            alert.addAction(UIAlertAction(title: "Sign In", style: .default) { _ in
                continuation.resume(returning: .auth(
                    username: alert.textFields?[0].text ?? "",
                    password: alert.textFields?[1].text ?? ""
                ))
            })
            present(alert, animated: true)
        }
    }

    private func presentChoicePrompt(_ request: SelectPromptRequest) async -> PromptResponse? {
        let choices = request.choices.flatMap { $0.items ?? [$0] }.filter { !$0.separator && !$0.disabled }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            for choice in choices {
                alert.addAction(UIAlertAction(title: choice.label, style: .default) { _ in
                    continuation.resume(returning: .choices([choice.id]))
                })
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            if let popover = alert.popoverPresentationController {
                popover.sourceView = geckoView
                popover.sourceRect = request.anchor.rect ?? geckoView.bounds
            }
            present(alert, animated: true)
        }
    }
}
