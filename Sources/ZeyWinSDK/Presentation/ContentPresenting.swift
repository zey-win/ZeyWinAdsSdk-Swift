import UIKit

@MainActor
protocol ContentPresenting {
    func presentLoading(
        from viewController: UIViewController
    )

    func dismissLoading()
    func dismissLoading(completion: @escaping () -> Void)

    func presentStickyBanner(
        content: SDKBannerContent,
        from viewController: UIViewController
    )

    func dismissStickyBanner()

    func present(
        action: SDKAction,
        from viewController: UIViewController,
        onClose: (() -> Void)?
    ) throws
}

extension ContentPresenting {
    func presentLoading(
        from viewController: UIViewController
    ) {}

    func dismissLoading() {}

    func dismissLoading(completion: @escaping () -> Void) { completion() }

    func presentStickyBanner(
        content: SDKBannerContent,
        from viewController: UIViewController
    ) {}

    func dismissStickyBanner() {}
}
