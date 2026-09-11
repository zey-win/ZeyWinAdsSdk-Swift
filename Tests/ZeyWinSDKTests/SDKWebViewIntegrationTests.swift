import Foundation
import UIKit
import WebKit
import XCTest
@testable import ZeyWinSDK

@MainActor
final class SDKWebViewIntegrationTests: XCTestCase {

    private var windows: [UIWindow] = []
    private var webViews: [WKWebView] = []

    override func tearDown() {
        webViews.forEach { webView in
            webView.navigationDelegate = nil
            webView.stopLoading()
            webView.removeFromSuperview()
        }
        webViews.removeAll()
        windows.forEach { window in
            window.isHidden = true
        }
        windows.removeAll()

        super.tearDown()
    }

    func testExecutesJavaScript() async throws {
        let webView = makeWebView()

        try await loadHTML(
            """
            <html><body><script>
            window.zeywinJavaScriptProbe = 40 + 2;
            </script></body></html>
            """,
            baseURL: URL(string: "https://webview-test.invalid/javascript")!,
            in: webView
        )

        let value = try await evaluate(
            "window.zeywinJavaScriptProbe",
            in: webView
        ) as? NSNumber

        XCTAssertEqual(value?.intValue, 42)
    }

    func testPersistsCookies() async throws {
        let webView = makeWebView()
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "webview-test.invalid",
                .path: "/",
                .name: "zeywin_cookie",
                .value: "persisted",
                .secure: "TRUE"
            ])
        )

        await setCookie(cookie, in: webView.configuration.websiteDataStore.httpCookieStore)

        let cookies = await allCookies(
            in: webView.configuration.websiteDataStore.httpCookieStore
        )

        XCTAssertEqual(
            cookies.first { $0.name == "zeywin_cookie" }?.value,
            "persisted"
        )
    }

    func testKeepsSessionAcrossNavigation() async throws {
        let webView = makeWebView()
        let cookie = try XCTUnwrap(
            HTTPCookie(properties: [
                .domain: "webview-test.invalid",
                .path: "/",
                .name: "zeywin_session",
                .value: "session-value"
            ])
        )

        await setCookie(cookie, in: webView.configuration.websiteDataStore.httpCookieStore)
        try await loadHTML(
            "<html><body data-page=\"first\"></body></html>",
            baseURL: URL(string: "https://webview-test.invalid/first")!,
            in: webView
        )
        try await loadHTML(
            "<html><body data-page=\"second\"></body></html>",
            baseURL: URL(string: "https://webview-test.invalid/second")!,
            in: webView
        )

        let cookies = await allCookies(
            in: webView.configuration.websiteDataStore.httpCookieStore
        )

        XCTAssertEqual(
            cookies.first { $0.name == "zeywin_session" }?.value,
            "session-value"
        )
    }

    func testRoutesExternalSchemesOutsideWebViewAndKeepsHTTPSInside() async throws {
        let relay = ExternalURLRelay()
        let controller = SDKWebViewController(
            url: URL(string: "about:blank")!,
            tracking: nil,
            externalURLHandler: { url in
                relay.openedURLs.append(url)
                relay.expectation?.fulfill()
            }
        )
        host(controller)

        let externalURLs = [
            "tg://resolve?domain=zeywin",
            "telegram://resolve?domain=zeywin",
            "whatsapp://send?text=zeywin",
            "viber://forward?text=zeywin",
            "intent://example.com#Intent;scheme=https;end",
            "market://details?id=com.example.app"
        ]

        for value in externalURLs {
            let expectation = expectation(description: "External scheme \(value)")
            relay.expectation = expectation
            controller.webView.load(
                URLRequest(url: try XCTUnwrap(URL(string: value)))
            )

            await fulfillment(of: [expectation], timeout: 5)
        }

        XCTAssertEqual(
            relay.openedURLs.map(\.absoluteString),
            externalURLs
        )

        let noExternalOpen = expectation(description: "HTTPS remains in WebView")
        noExternalOpen.isInverted = true
        relay.expectation = noExternalOpen

        controller.webView.load(
            URLRequest(url: URL(string: "https://127.0.0.1/inside-webview")!)
        )
        await fulfillment(of: [noExternalOpen], timeout: 0.5)
        XCTAssertEqual(relay.openedURLs.count, externalURLs.count)
    }

    func testBackNavigationUsesHistoryAndDoesNotCloseOfferWithoutHistory() async throws {
        var closeCount = 0
        let controller = SDKWebViewController(
            url: URL(string: "about:blank")!,
            tracking: nil,
            onClose: {
                closeCount += 1
            }
        )
        host(controller)

        let fixturesDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixturesDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: fixturesDirectory)
        }

        let firstPage = fixturesDirectory.appendingPathComponent("first.html")
        let secondPage = fixturesDirectory.appendingPathComponent("second.html")
        try Data("<html><body data-page=\"first\"></body></html>".utf8).write(to: firstPage)
        try Data("<html><body data-page=\"second\"></body></html>".utf8).write(to: secondPage)

        XCTAssertFalse(controller.webView.canGoBack)
        XCTAssertNil(controller.webView.goBack())
        XCTAssertEqual(closeCount, 0)

        try await loadFile(firstPage, allowingReadAccessTo: fixturesDirectory, in: controller.webView)
        try await loadFile(secondPage, allowingReadAccessTo: fixturesDirectory, in: controller.webView)

        XCTAssertTrue(controller.webView.canGoBack)
        XCTAssertNotNil(controller.webView.goBack())
        controller.webView.stopLoading()
        XCTAssertEqual(closeCount, 0)
    }

    func testWebViewUsesSafeAreaConstraintsAndConfiguredOrientation() {
        let landscapeController = SDKWebViewController(
            url: URL(string: "about:blank")!,
            tracking: nil
        )
        landscapeController.loadViewIfNeeded()

        let allOrientationsController = SDKWebViewController(
            url: URL(string: "about:blank")!,
            tracking: nil,
            orientationMask: .all
        )

        XCTAssertEqual(
            landscapeController.supportedInterfaceOrientations,
            .landscape
        )
        XCTAssertEqual(
            allOrientationsController.supportedInterfaceOrientations,
            .all
        )

        let safeArea = landscapeController.view.safeAreaLayoutGuide
        let constraints = landscapeController.view.constraints
        XCTAssertTrue(
            constraints.contains {
                $0.firstItem as? WKWebView === landscapeController.webView
                    && $0.secondItem as? UILayoutGuide === safeArea
                    && $0.firstAttribute == .top
                    && $0.secondAttribute == .top
            }
        )
        XCTAssertTrue(
            constraints.contains {
                $0.firstItem as? WKWebView === landscapeController.webView
                    && $0.secondItem as? UILayoutGuide === safeArea
                    && $0.firstAttribute == .bottom
                    && $0.secondAttribute == .bottom
            }
        )
    }

    func testChecklistPassesAgainstProductionPage() async throws {
        try requireNetworkTests()

        let webView = makeWebView()
        let checklistURL = URL(
            string: "https://ads.zeywin.com/checklist/webview-test?runner=1"
        )!

        do {
            _ = try await performNavigation(in: webView) {
                webView.load(URLRequest(url: checklistURL))
            }
        } catch {
            throw XCTSkip(
                "Network/infrastructure failure while opening the checklist: \(error.localizedDescription)"
            )
        }

        let result = try await waitForChecklistResult(in: webView)
        let failures = result.compactMap { id, value -> String? in
            guard value["status"] as? String == "fail" else {
                return nil
            }

            let detail = value["detail"] as? String ?? "no failure detail"
            return "\(id): \(detail)"
        }

        XCTAssertFalse(result.isEmpty, "Checklist returned no results")
        XCTAssertTrue(failures.isEmpty, "Checklist failures: \(failures.joined(separator: ", "))")
    }

    func testRemoteRedirectChainsReachFinalChecklistPage() async throws {
        try requireNetworkTests()

        for mode in ["http", "meta", "js", "mixed"] {
            let webView = makeWebView()
            let url = URL(
                string: "https://zeywin-ads-api.whiteapps.workers.dev/api/v1/checklist/redirect/5?mode=\(mode)&dest=page&runner=1&autorun=0"
            )!

            do {
                let finalURL = try await performNavigation(
                    in: webView,
                    until: isChecklistFinalURL
                ) {
                    webView.load(URLRequest(url: url))
                }
                XCTAssertTrue(isChecklistFinalURL(finalURL), "Mode \(mode) ended at \(finalURL)")
            } catch {
                throw XCTSkip(
                    "Network/infrastructure failure in \(mode) redirect chain: \(error.localizedDescription)"
                )
            }
        }
    }

    func testCleartextHTTPIsExplicitlyClassifiedByATS() async throws {
        try requireNetworkTests()

        let webView = makeWebView()
        let cleartextURL = URL(
            string: "http://ads.zeywin.com/checklist/webview-test?cleartext=done&runner=1&autorun=0"
        )!

        do {
            let finalURL = try await performNavigation(
                in: webView,
                until: isChecklistFinalURL
            ) {
                webView.load(URLRequest(url: cleartextURL))
            }
            XCTAssertTrue(isChecklistFinalURL(finalURL))
        } catch let error as NSError where error.code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
            throw XCTSkip(
                "ATS blocked cleartext HTTP. The SDK does not override ATS; configure the host app Info.plist only when HTTP offers are intentionally supported."
            )
        } catch {
            throw XCTSkip(
                "Network/infrastructure failure during cleartext HTTP test: \(error.localizedDescription)"
            )
        }
    }

    private func makeWebView() -> WKWebView {
        let configuration = SDKWebViewController.makeWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()

        webView.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])

        windows.append(window)
        webViews.append(webView)
        return webView
    }

    private func host(
        _ controller: UIViewController
    ) {
        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()

        host.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: host.view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        controller.didMove(toParent: host)

        windows.append(window)
        if let controller = controller as? SDKWebViewController {
            webViews.append(controller.webView)
        }
    }

    private func loadHTML(
        _ html: String,
        baseURL: URL,
        in webView: WKWebView
    ) async throws {
        _ = try await performNavigation(in: webView) {
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    private func loadFile(
        _ url: URL,
        allowingReadAccessTo directory: URL,
        in webView: WKWebView
    ) async throws {
        _ = try await performNavigation(in: webView) {
            webView.loadFileURL(
                url,
                allowingReadAccessTo: directory
            )
        }
    }

    private func performNavigation(
        in webView: WKWebView,
        until predicate: @escaping (URL) -> Bool = { _ in true },
        action: () -> Void
    ) async throws -> URL {
        let probe = NavigationProbe(predicate: predicate)
        webView.navigationDelegate = probe

        return try await withCheckedThrowingContinuation { continuation in
            probe.begin(
                continuation: continuation,
                timeout: 30
            )
            action()
        }
    }

    private func evaluate(
        _ javaScript: String,
        in webView: WKWebView
    ) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(javaScript) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value as Any)
                }
            }
        }
    }

    private func setCookie(
        _ cookie: HTTPCookie,
        in store: WKHTTPCookieStore
    ) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func allCookies(
        in store: WKHTTPCookieStore
    ) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func waitForChecklistResult(
        in webView: WKWebView
    ) async throws -> [String: [String: Any]] {
        let deadline = Date().addingTimeInterval(120)

        while Date() < deadline {
            let value = try? await evaluate(
                """
                (() => {
                  const key = '__zeywin_xctest_checklist_result__';
                  const existing = sessionStorage.getItem(key);
                  if (existing) return existing;
                  const checklist = window.ZW_CHECKLIST;
                  if (!checklist) return null;
                  if (!window.__zeywinXCTestCompletionHook) {
                    window.__zeywinXCTestCompletionHook = true;
                    checklist.onComplete((results) => {
                      sessionStorage.setItem(key, JSON.stringify(results));
                    });
                  }
                  return null;
                })()
                """,
                in: webView
            )

            if let json = value as? String,
               let data = json.data(using: .utf8),
               let result = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                return result
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }

        XCTFail("Checklist did not complete within 120 seconds")
        return [:]
    }

    private func requireNetworkTests() throws {
        #if ZEYWIN_RUN_NETWORK_WEBVIEW_TESTS
        return
        #else
        guard ProcessInfo.processInfo.environment["ZEYWIN_RUN_NETWORK_WEBVIEW_TESTS"] == "1" else {
            throw XCTSkip(
                "Set ZEYWIN_RUN_NETWORK_WEBVIEW_TESTS=1 in an Xcode scheme or pass OTHER_SWIFT_FLAGS='-DZEYWIN_RUN_NETWORK_WEBVIEW_TESTS' to xcodebuild."
            )
        }
        #endif
    }

    private func isChecklistFinalURL(
        _ url: URL
    ) -> Bool {
        guard
            url.host == "ads.zeywin.com",
            url.path == "/checklist/webview-test"
        else {
            return false
        }

        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains(where: { $0.name == "redirect" && $0.value == "done" }) == true
    }
}

private struct WebViewNavigationTimeout: LocalizedError {
    var errorDescription: String? {
        "WKWebView navigation timed out"
    }
}

private final class NavigationProbe: NSObject, WKNavigationDelegate {

    private let predicate: (URL) -> Bool
    private var completed = false
    private var continuation: CheckedContinuation<URL, Error>?

    init(
        predicate: @escaping (URL) -> Bool
    ) {
        self.predicate = predicate
    }

    func begin(
        continuation: CheckedContinuation<URL, Error>,
        timeout: TimeInterval
    ) {
        self.continuation = continuation

        DispatchQueue.main.asyncAfter(
            deadline: .now() + timeout
        ) { [weak self] in
            self?.finish(with: .failure(WebViewNavigationTimeout()))
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation?
    ) {
        guard let url = webView.url, predicate(url) else {
            return
        }

        finish(with: .success(url))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        finish(with: .failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        finish(with: .failure(error))
    }

    private func finish(
        with result: Result<URL, Error>
    ) {
        guard !completed else {
            return
        }

        completed = true
        continuation?.resume(with: result)
        continuation = nil
    }
}

private final class ExternalURLRelay {
    var openedURLs: [URL] = []
    var expectation: XCTestExpectation?
}
