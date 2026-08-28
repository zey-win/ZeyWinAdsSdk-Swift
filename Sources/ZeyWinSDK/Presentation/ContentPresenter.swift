import UIKit

@MainActor
final class ContentPresenter: ContentPresenting {

    private weak var loadingViewController: SDKLoadingViewController?
    private weak var bannerView: SDKBannerView?
    private weak var promoModalView: SDKPromoModalView?
    private weak var bannerHostViewController: UIViewController?
    private var activeBannerContent: SDKBannerContent?
    private var bannerHiddenForFullscreen = false
    private var promoTimer: Timer?

    func presentLoading(
        from viewController: UIViewController
    ) {
        dismissLoading()

        let loadingViewController = SDKLoadingViewController()
        loadingViewController.view.translatesAutoresizingMaskIntoConstraints = false

        viewController.addChild(loadingViewController)
        viewController.view.addSubview(loadingViewController.view)

        NSLayoutConstraint.activate([
            loadingViewController.view.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            loadingViewController.view.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            loadingViewController.view.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            loadingViewController.view.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
        ])

        loadingViewController.didMove(toParent: viewController)

        self.loadingViewController = loadingViewController
    }

    func dismissLoading() {
        guard let loadingViewController else {
            return
        }

        loadingViewController.willMove(toParent: nil)
        loadingViewController.view.removeFromSuperview()
        loadingViewController.removeFromParent()
        self.loadingViewController = nil
    }

    func present(
        action: SDKAction,
        from viewController: UIViewController
    ) throws {
        dismissLoading()

        switch action {

        case .offer(let url):
            dismissStickyBanner()
            presentWebView(
                url: url,
                from: viewController
            )

        case .internalAd(let content):
            hideStickyBannerForFullscreen()
            presentWebView(
                url: content.mediaURL,
                clickThroughURL: content.targetURL,
                tracking: content.tracking,
                durationSec: content.durationSec,
                skipAfterSec: content.skipAfterSec,
                from: viewController,
                onClose: { [weak self] in
                    Task { @MainActor in
                        self?.restoreStickyBannerAfterFullscreen()
                    }
                }
            )

        case .banner(let content):
            presentStickyBanner(
                content: content,
                from: viewController
            )

        case .blocked, .none:
            stopPromoTimer()
            break
        }
    }

    private func presentWebView(
        url: URL,
        clickThroughURL: URL? = nil,
        tracking: SDKAdTracking? = nil,
        durationSec: Int? = nil,
        skipAfterSec: Int? = nil,
        from viewController: UIViewController,
        onClose: (() -> Void)? = nil
    ) {
        let webViewController = SDKWebViewController(
            url: url,
            clickThroughURL: clickThroughURL,
            tracking: tracking ?? SDKTrackingRegistry.shared.tracking(for: url),
            durationSec: durationSec,
            skipAfterSec: skipAfterSec,
            onClose: onClose
        )

        webViewController.modalPresentationStyle = .fullScreen

        viewController.present(
            webViewController,
            animated: true
        )
    }

    func presentStickyBanner(
        content: SDKBannerContent,
        from viewController: UIViewController
    ) {
        dismissStickyBanner()
        activeBannerContent = content
        bannerHostViewController = viewController
        bannerHiddenForFullscreen = false

        SDKTrackingClient.shared.fire(
            content.tracking,
            event: "impression"
        )

        let banner = SDKBannerView(
            content: content,
            onClick: { [weak self] url in
                self?.openAdURL(
                    url,
                    tracking: content.tracking
                )
            }
        )

        viewController.view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(
                equalTo: viewController.view.leadingAnchor
            ),
            banner.trailingAnchor.constraint(
                equalTo: viewController.view.trailingAnchor
            ),
            banner.bottomAnchor.constraint(
                equalTo: viewController.view.bottomAnchor
            ),
            banner.heightAnchor.constraint(
                equalToConstant: 57
            )
        ])

        bannerView = banner
        schedulePromoModalIfNeeded(
            content: content,
            from: viewController
        )
    }

    func dismissStickyBanner() {
        bannerView?.removeFromSuperview()
        bannerView = nil
        activeBannerContent = nil
        bannerHostViewController = nil
        bannerHiddenForFullscreen = false
        stopPromoTimer()
    }

    private func hideStickyBannerForFullscreen() {
        guard bannerView != nil else {
            return
        }

        bannerHiddenForFullscreen = true
        bannerView?.removeFromSuperview()
        bannerView = nil
        stopPromoTimer()
    }

    private func restoreStickyBannerAfterFullscreen() {
        guard
            bannerHiddenForFullscreen,
            let activeBannerContent,
            let bannerHostViewController
        else {
            return
        }

        bannerHiddenForFullscreen = false
        presentStickyBanner(
            content: activeBannerContent,
            from: bannerHostViewController
        )
    }

    private func schedulePromoModalIfNeeded(
        content: SDKBannerContent,
        from viewController: UIViewController
    ) {
        stopPromoTimer()

        let delay = TimeInterval(content.popupDelaySec ?? 30)
        let repeatInterval = TimeInterval(content.popupRepeatSec ?? 30)

        promoTimer = Timer.scheduledTimer(
            withTimeInterval: max(1, delay),
            repeats: false
        ) { [weak self, weak viewController] _ in
            Task { @MainActor in
                guard
                    let self,
                    let viewController
                else {
                    return
                }

                self.presentPromoModal(
                    content: content,
                    from: viewController
                )

                guard repeatInterval > 0 else {
                    self.promoTimer = nil
                    return
                }

                self.promoTimer = Timer.scheduledTimer(
                    withTimeInterval: max(1, repeatInterval),
                    repeats: true
                ) { [weak self, weak viewController] _ in
                    Task { @MainActor in
                        guard
                            let self,
                            let viewController
                        else {
                            return
                        }

                        self.presentPromoModal(
                            content: content,
                            from: viewController
                        )
                    }
                }
            }
        }
    }

    private func presentPromoModal(
        content: SDKBannerContent,
        from viewController: UIViewController
    ) {
        promoModalView?.removeFromSuperview()

        let modal = SDKPromoModalView(
            content: content,
            onClick: { [weak self] url in
                self?.openAdURL(
                    url,
                    tracking: content.tracking
                )
            },
            onClose: { [weak self] in
                self?.promoModalView = nil
            }
        )

        viewController.view.addSubview(modal)

        NSLayoutConstraint.activate([
            modal.leadingAnchor.constraint(
                equalTo: viewController.view.leadingAnchor,
                constant: 16
            ),
            modal.trailingAnchor.constraint(
                equalTo: viewController.view.trailingAnchor,
                constant: -16
            ),
            modal.bottomAnchor.constraint(
                equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor,
                constant: -62
            ),
            modal.heightAnchor.constraint(
                equalToConstant: 106
            )
        ])

        promoModalView = modal
    }


    private func openAdURL(
        _ url: URL,
        tracking: SDKAdTracking?
    ) {
        SDKTrackingClient.shared.fire(
            tracking,
            event: "click"
        )

        UIApplication.shared.open(url)
    }

    private func stopPromoTimer() {
        promoTimer?.invalidate()
        promoTimer = nil
        promoModalView?.removeFromSuperview()
        promoModalView = nil
    }
}
