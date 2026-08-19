import UIKit

@MainActor
final class ContentPresenter: ContentPresenting {

    func present(
        action: SDKAction,
        from viewController: UIViewController
    ) throws {

        switch action {

        case .offer(let url):
            presentWebView(
                url: url,
                from: viewController
            )

        case .internalAd(let content):
            presentWebView(
                url: content.mediaURL,
                clickThroughURL: content.targetURL,
                tracking: content.tracking,
                from: viewController
            )

        case .banner(let content):
            presentBanner(
                content: content,
                from: viewController
            )

        case .blocked, .none:
            break
        }
    }

    private func presentWebView(
        url: URL,
        clickThroughURL: URL? = nil,
        tracking: SDKAdTracking? = nil,
        from viewController: UIViewController
    ) {
        let webViewController = SDKWebViewController(
            url: url,
            clickThroughURL: clickThroughURL,
            tracking: tracking ?? SDKTrackingRegistry.shared.tracking(for: url)
        )

        webViewController.modalPresentationStyle = .fullScreen

        viewController.present(
            webViewController,
            animated: true
        )
    }

    private func presentBanner(
        content: SDKBannerContent,
        from viewController: UIViewController
    ) {
        SDKTrackingClient.shared.fire(
            content.tracking,
            event: "impression"
        )

        let banner = SDKBannerView(
            content: content
        )

        viewController.view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(
                equalTo: viewController.view.leadingAnchor,
                constant: 16
            ),
            banner.trailingAnchor.constraint(
                equalTo: viewController.view.trailingAnchor,
                constant: -16
            ),
            banner.bottomAnchor.constraint(
                equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor,
                constant: -12
            ),
            banner.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 56
            )
        ])
    }
}
