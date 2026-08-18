import UIKit
import WebKit

@MainActor
final class SDKWebViewController: UIViewController {

    private let url: URL
    private let tracking: SDKAdTracking?
    private var didSendClickTracking = false
    private let webView = WKWebView(
        frame: .zero,
        configuration: WKWebViewConfiguration()
    )

    init(
        url: URL,
        tracking: SDKAdTracking?
    ) {
        self.url = url
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

        title = "Content"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
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
        ])

        webView.load(
            URLRequest(url: url)
        )

        SDKTrackingClient.shared.fire(
            tracking,
            event: "impression"
        )
    }

    @objc
    private func closeTapped() {
        dismiss(animated: true)
    }
}

extension SDKWebViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if
            navigationAction.navigationType == .linkActivated,
            !didSendClickTracking
        {
            didSendClickTracking = true
            SDKTrackingClient.shared.fire(
                tracking,
                event: "click"
            )
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        SDKLogger.log(
            "WebView navigation error: \(error.localizedDescription)"
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        SDKLogger.log(
            "WebView provisional navigation error: \(error.localizedDescription)"
        )
    }
}
