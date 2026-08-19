import UIKit
import WebKit

@MainActor
final class SDKWebViewController: UIViewController {

    private let url: URL
    private let clickThroughURL: URL?
    private let tracking: SDKAdTracking?
    private var didSendClickTracking = false
    private var didSendShownTracking = false
    private var didSendFailedTracking = false
    private let webView = WKWebView(
        frame: .zero,
        configuration: SDKWebViewController.makeWebViewConfiguration()
    )
    private let clickOverlay = UIControl()

    init(
        url: URL,
        clickThroughURL: URL? = nil,
        tracking: SDKAdTracking?
    ) {
        self.url = url
        self.clickThroughURL = clickThroughURL
        self.tracking = tracking
        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        setupWebView()
        setupClickOverlayIfNeeded()

        SDKTrackingClient.shared.fire(
            tracking,
            event: "impression"
        )
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)

        NSLayoutConstraint.activate(
            [
                webView.topAnchor.constraint(
                    equalTo: view.topAnchor
                ),
                webView.leadingAnchor.constraint(
                    equalTo: view.leadingAnchor
                ),
                webView.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor
                ),
                webView.bottomAnchor.constraint(
                    equalTo: view.bottomAnchor
                )
            ]
        )

        if isDirectVideoURL(url) {
            webView.loadHTMLString(
                videoHTML(for: url),
                baseURL: url.deletingLastPathComponent()
            )
        } else {
            webView.load(
                URLRequest(url: url)
            )
        }
    }

    private func setupClickOverlayIfNeeded() {
        guard clickThroughURL != nil else {
            return
        }

        clickOverlay.backgroundColor = .clear
        clickOverlay.translatesAutoresizingMaskIntoConstraints = false
        clickOverlay.addTarget(
            self,
            action: #selector(openClickThrough),
            for: .touchUpInside
        )
        view.addSubview(
            clickOverlay
        )

        NSLayoutConstraint.activate(
            [
                clickOverlay.topAnchor.constraint(
                    equalTo: view.topAnchor
                ),
                clickOverlay.leadingAnchor.constraint(
                    equalTo: view.leadingAnchor
                ),
                clickOverlay.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor
                ),
                clickOverlay.bottomAnchor.constraint(
                    equalTo: view.bottomAnchor
                )
            ]
        )
    }

    private func isDirectVideoURL(
        _ url: URL
    ) -> Bool {
        let path = url.path.lowercased()

        return path.hasSuffix(".mp4")
            || path.hasSuffix(".mov")
            || path.hasSuffix(".m4v")
            || path.hasSuffix(".webm")
    }

    private func videoHTML(
        for url: URL
    ) -> String {
        let source = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        html, body {
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
            overflow: hidden;
            background: #000;
        }
        video {
            width: 100vw;
            height: 100vh;
            object-fit: contain;
            background: #000;
        }
        </style>
        </head>
        <body>
        <video id="creative" src="\(source)" autoplay muted playsinline loop preload="auto"></video>
        <script>
        const creative = document.getElementById('creative');
        let reported = false;

        function reportShown() {
            if (reported) { return; }
            reported = true;
            window.location.href = 'zeywin-sdk://webview-shown';
        }

        function reportFailed() {
            window.location.href = 'zeywin-sdk://webview-failed?reason=video_error';
        }

        creative.addEventListener('canplay', reportShown);
        creative.addEventListener('playing', reportShown);
        creative.addEventListener('error', reportFailed);
        creative.play().catch(function() {});
        </script>
        </body>
        </html>
        """
    }

    private static func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        return configuration
    }

    @objc
    private func openClickThrough() {
        guard let clickThroughURL else {
            return
        }

        trackClickIfNeeded()
        clickOverlay.removeFromSuperview()

        webView.load(
            URLRequest(url: clickThroughURL)
        )
    }
}

extension SDKWebViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation?
    ) {
        if !isDirectVideoURL(url) {
            trackWebViewShownIfNeeded()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if handleSDKNavigation(
            navigationAction.request.url
        ) {
            decisionHandler(.cancel)
            return
        }

        if
            navigationAction.navigationType == .linkActivated,
            let clickThroughURL
        {
            trackClickIfNeeded()

            webView.load(
                URLRequest(url: clickThroughURL)
            )

            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    private func handleSDKNavigation(
        _ url: URL?
    ) -> Bool {
        guard url?.scheme == "zeywin-sdk" else {
            return false
        }

        switch url?.host {
        case "webview-shown":
            trackWebViewShownIfNeeded()

        case "webview-failed":
            trackWebViewFailure(
                reason: "video_error"
            )

        default:
            break
        }

        return true
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        if isPluginHandledLoadError(error) {
            trackWebViewShownIfNeeded()
            return
        }

        SDKLogger.log(
            "WebView navigation error: \(error.localizedDescription)"
        )

        trackWebViewFailure(
            reason: "html_load_error"
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        if isPluginHandledLoadError(error) {
            trackWebViewShownIfNeeded()
            return
        }

        SDKLogger.log(
            "WebView provisional navigation error: \(error.localizedDescription)"
        )

        trackWebViewFailure(
            reason: "html_load_error"
        )
    }

    private func trackWebViewFailure(
        reason: String
    ) {
        guard
            !didSendShownTracking,
            !didSendFailedTracking
        else {
            return
        }

        didSendFailedTracking = true
        SDKTrackingClient.shared.trackWebView(
            tracking,
            status: "failed",
            failReason: reason
        )
    }

    private func trackWebViewShownIfNeeded() {
        guard !didSendShownTracking else {
            return
        }

        didSendShownTracking = true
        SDKTrackingClient.shared.trackWebView(
            tracking,
            status: "shown"
        )
    }

    private func isPluginHandledLoadError(
        _ error: Error
    ) -> Bool {
        let nsError = error as NSError

        return nsError.domain == "WebKitErrorDomain"
            && nsError.code == 204
    }

    private func trackClickIfNeeded() {
        guard !didSendClickTracking else {
            return
        }

        didSendClickTracking = true
        SDKTrackingClient.shared.fire(
            tracking,
            event: "click"
        )
    }
}
