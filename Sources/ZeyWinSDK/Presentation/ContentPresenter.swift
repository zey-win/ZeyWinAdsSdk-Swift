import UIKit

@MainActor
final class ContentPresenter: ContentPresenting {

    private var loadingViewController: SDKLoadingViewController?
    private weak var bannerView: SDKBannerView?
    private weak var promoModalView: SDKPromoModalView?
    private weak var bannerHostViewController: UIViewController?
    private var overlayWindow: SDKOverlayWindow?
    private var activeBannerContent: SDKBannerContent?
    private var bannerHiddenForFullscreen = false
    private var promoTimer: Timer?

    func presentLoading(
        from viewController: UIViewController
    ) {
        dismissLoadingImmediately()

        let loadingViewController = SDKLoadingViewController()
        loadingViewController.view.translatesAutoresizingMaskIntoConstraints = false
        loadingViewController.view.isOpaque = true
        loadingViewController.view.alpha = 1

        let hostView = overlayView(for: viewController, orientationMask: .all)
        hostView.addSubview(loadingViewController.view)

        NSLayoutConstraint.activate([
            loadingViewController.view.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            loadingViewController.view.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            loadingViewController.view.topAnchor.constraint(equalTo: hostView.topAnchor),
            loadingViewController.view.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
        ])

        hostView.bringSubviewToFront(loadingViewController.view)

        self.loadingViewController = loadingViewController
    }

    func dismissLoading() {
        dismissLoading {}
    }

    func dismissLoading(completion: @escaping () -> Void) {
        finishLoadingThenPresent(completion)
    }

    private func dismissLoadingImmediately() {
        guard let loadingViewController else {
            return
        }

        loadingViewController.willMove(toParent: nil)
        loadingViewController.view.removeFromSuperview()
        loadingViewController.removeFromParent()
        self.loadingViewController = nil
        removeOverlayWindowIfEmpty()
    }

    private func finishLoadingThenPresent(_ completion: @escaping () -> Void) {
        guard let loadingViewController else {
            completion()
            return
        }

        loadingViewController.completeAndDismiss { [weak self, weak loadingViewController] in
            guard let self else {
                return
            }

            loadingViewController?.willMove(toParent: nil)
            loadingViewController?.view.removeFromSuperview()
            loadingViewController?.removeFromParent()
            self.loadingViewController = nil
            self.removeOverlayWindowIfEmpty()
            completion()
        }
    }

    func present(
        action: SDKAction,
        from viewController: UIViewController,
        onClose: (() -> Void)?
    ) throws {
        if case .offer(let url) = action {
            dismissStickyBanner()
            presentWebView(
                url: url,
                from: viewController,
                orientationMask: .all,
                onClose: onClose,
                onReady: { [weak self] in
                    self?.finishLoadingThenPresent {}
                }
            )
            return
        }

        finishLoadingThenPresent { [weak self, weak viewController] in
            guard
                let self,
                let viewController
            else {
                return
            }

            switch action {
            case .internalAd(let content):
                self.hideStickyBannerForFullscreen()
                self.presentWebView(
                    url: content.mediaURL,
                    clickThroughURL: content.targetURL,
                    tracking: content.tracking,
                    durationSec: content.durationSec,
                    skipAfterSec: content.skipAfterSec,
                    from: viewController,
                    orientationMask: .landscape,
                    onClose: { [weak self] in
                        self?.restoreStickyBannerAfterFullscreen()
                    }
                )

            case .banner(let content):
                self.presentStickyBanner(
                    content: content,
                    from: viewController
                )

            case .blocked, .none:
                self.stopPromoTimer()

            case .offer:
                break
            }
        }
    }

    private func presentWebView(
        url: URL,
        clickThroughURL: URL? = nil,
        tracking: SDKAdTracking? = nil,
        durationSec: Int? = nil,
        skipAfterSec: Int? = nil,
        from viewController: UIViewController,
        orientationMask: UIInterfaceOrientationMask = .landscape,
        onClose: (() -> Void)? = nil,
        onReady: (() -> Void)? = nil
    ) {
        let webViewController = SDKWebViewController(
            url: url,
            clickThroughURL: clickThroughURL,
            tracking: tracking ?? SDKTrackingRegistry.shared.tracking(for: url),
            durationSec: durationSec,
            skipAfterSec: skipAfterSec,
            orientationMask: orientationMask,
            onClose: onClose,
            onReady: onReady
        )

        webViewController.modalPresentationStyle = .fullScreen

        viewController.present(
            webViewController,
            animated: onReady == nil
        )
    }

    func presentStickyBanner(
        content: SDKBannerContent,
        from viewController: UIViewController
    ) {
        dismissStickyBanner()
        activeBannerContent = content
        bannerHostViewController = viewController
        let hostView = overlayView(for: viewController, orientationMask: .landscape)
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

        hostView.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(
                equalTo: hostView.leadingAnchor
            ),
            banner.trailingAnchor.constraint(
                equalTo: hostView.trailingAnchor
            ),
            banner.bottomAnchor.constraint(
                equalTo: hostView.bottomAnchor
            ),
            banner.heightAnchor.constraint(
                equalToConstant: 38
            )
        ])

        hostView.bringSubviewToFront(banner)
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
        removeOverlayWindowIfEmpty()
    }

    private func hideStickyBannerForFullscreen() {
        guard bannerView != nil else {
            return
        }

        bannerHiddenForFullscreen = true
        bannerView?.removeFromSuperview()
        bannerView = nil
        stopPromoTimer()
        removeOverlayWindowIfEmpty()
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
                self?.removeOverlayWindowIfEmpty()
            }
        )

        let hostView = overlayView(for: viewController, orientationMask: .landscape)
        hostView.addSubview(modal)

        NSLayoutConstraint.activate([
            modal.leadingAnchor.constraint(
                equalTo: hostView.safeAreaLayoutGuide.leadingAnchor,
                constant: 12
            ),
            modal.trailingAnchor.constraint(
                equalTo: hostView.safeAreaLayoutGuide.trailingAnchor,
                constant: -12
            ),
            modal.bottomAnchor.constraint(
                equalTo: hostView.bottomAnchor,
                constant: -8
            ),
            modal.heightAnchor.constraint(
                equalToConstant: 106
            )
        ])

        hostView.bringSubviewToFront(modal)
        promoModalView = modal
    }



    private func overlayView(for viewController: UIViewController, orientationMask: UIInterfaceOrientationMask) -> UIView {
        if let overlayWindow {
            if let rootViewController = overlayWindow.rootViewController as? SDKOverlayViewController {
                rootViewController.updateOrientationMask(orientationMask)
                return rootViewController.view
            }

            return overlayWindow.rootViewController?.view ?? overlayWindow
        }

        guard let windowScene = viewController.view.window?.windowScene
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else {
            return viewController.view
        }

        let overlayWindow = SDKOverlayWindow(windowScene: windowScene)
        overlayWindow.frame = windowScene.coordinateSpace.bounds
        overlayWindow.backgroundColor = .clear
        overlayWindow.windowLevel = .alert - 1
        overlayWindow.isHidden = false

        let rootViewController = SDKOverlayViewController(orientationMask: orientationMask)
        overlayWindow.rootViewController = rootViewController

        self.overlayWindow = overlayWindow

        return rootViewController.view
    }

    private func removeOverlayWindowIfEmpty() {
        guard
            loadingViewController == nil,
            bannerView == nil,
            promoModalView == nil
        else {
            return
        }

        overlayWindow?.isHidden = true
        overlayWindow = nil
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
        removeOverlayWindowIfEmpty()
    }
}

private final class SDKOverlayViewController: UIViewController {
    private var orientationMask: UIInterfaceOrientationMask

    init(orientationMask: UIInterfaceOrientationMask) {
        self.orientationMask = orientationMask
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        orientationMask
    }

    override var shouldAutorotate: Bool {
        true
    }

    func updateOrientationMask(_ orientationMask: UIInterfaceOrientationMask) {
        self.orientationMask = orientationMask
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

private final class SDKOverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)

        if hitView === rootViewController?.view {
            return nil
        }

        return hitView
    }
}
