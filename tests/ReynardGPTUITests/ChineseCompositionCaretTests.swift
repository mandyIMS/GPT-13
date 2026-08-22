import XCTest

final class ChineseCompositionCaretTests: XCTestCase {
    private let diagnosticPage = """
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
      <style>
        * { box-sizing: border-box; }
        html, body { margin: 0; width: 100%; height: 100%; background: #f7f7f8; }
        body { font: 17px -apple-system, sans-serif; }
        #composer {
          position: fixed; left: 16px; right: 16px; bottom: 24px;
          min-height: 58px; padding: 17px 18px; border: 1px solid #bbb;
          border-radius: 20px; background: white; color: black;
          outline: none; caret-color: #111; white-space: pre-wrap;
        }
        #composer p { margin: 0; min-height: 1.25em; }
        #composer p.is-editor-empty:first-child::before {
          content: '给 GPT 发消息'; color: #777; float: left;
          height: 0; pointer-events: none;
        }
      </style>
    </head>
    <body>
      <div id="composer" class="ProseMirror" role="textbox"
           aria-label="GPT 测试输入框" contenteditable="true" translate="no"><p class="is-editor-empty"><br class="ProseMirror-trailingBreak"></p></div>
      <script>
        const composer = document.getElementById('composer');
        const markNonEmpty = () => composer.querySelector('p')?.classList.remove('is-editor-empty');
        document.addEventListener('click', () => composer.focus());
        composer.addEventListener('focus', () => composer.style.borderColor = '#00a67e');
        composer.addEventListener('compositionstart', markNonEmpty);
        composer.addEventListener('beforeinput', markNonEmpty);
        composer.addEventListener('input', markNonEmpty);
      </script>
    </body>
    </html>
    """

    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testChinesePinyinCompositionCaret() throws {
        let app = XCUIApplication()
        app.launchEnvironment["REYNARD_IME_DIAGNOSTICS"] = "1"
        let encodedPage = Data(diagnosticPage.utf8).base64EncodedString()
        app.launchEnvironment["REYNARD_UI_TEST_URL"] = "data:text/html;charset=utf-8;base64,\(encodedPage)"
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        sleep(8)
        keepScreenshot("01-page-loaded")

        let candidateOffsets: [CGVector] = [
            CGVector(dx: 0.50, dy: 0.45),
            CGVector(dx: 0.50, dy: 0.69),
            CGVector(dx: 0.50, dy: 0.63),
            CGVector(dx: 0.50, dy: 0.74),
        ]
        for offset in candidateOffsets where !app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: offset).tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        }

        keepScreenshot("02-composer-focused")
        XCTAssertTrue(
            app.keyboards.firstMatch.exists,
            "The Gecko contenteditable did not become first responder"
        )
        guard app.keyboards.firstMatch.exists else { return }

        // Tap the visible software-keyboard keys instead of injecting the
        // whole string at once. This guarantees that the Chinese keyboard's
        // marked-text path runs and gives us a frame after every composition
        // update.
        for (index, letter) in ["n", "i", "h", "a", "o"].enumerated() {
            let key = app.keys[letter]
            if key.waitForExistence(timeout: 2) {
                // iOS 15's accessibility server tries (and fails) to scroll
                // software-keyboard keys before a normal XCUIElement tap in
                // compatibility-mode apps. Tap the key's visible midpoint
                // directly so the real Pinyin software keyboard handles it.
                let frame = key.frame
                let appFrame = app.frame
                let offset = CGVector(
                    dx: frame.midX / appFrame.width,
                    dy: frame.midY / appFrame.height
                )
                app.coordinate(withNormalizedOffset: offset).tap()
            } else {
                app.typeText(letter)
            }
            usleep(300_000)
            keepScreenshot(String(format: "03-composition-%02d-%@", index, letter))
        }

        // A blinking caret alternates between visible and hidden frames. Keep
        // several stationary frames so a single unlucky screenshot cannot be
        // mistaken for a permanently missing caret.
        for index in 0..<6 {
            usleep(250_000)
            keepScreenshot(String(format: "04-caret-blink-%02d", index))
        }

        // Tap the first candidate in the Simplified Chinese Pinyin candidate
        // bar. The keyboard frame reported by iOS 15 accessibility is not
        // reliable for this compatibility-mode app, so use a stable screen
        // location within the visible candidate row.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.55)).tap()
        usleep(500_000)
        keepScreenshot("05-after-candidate-commit")

        for index in 0..<4 {
            usleep(250_000)
            keepScreenshot(String(format: "06-plain-caret-blink-%02d", index))
        }
    }
}
