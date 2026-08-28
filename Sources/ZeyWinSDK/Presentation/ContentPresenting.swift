import UIKit

@MainActor
protocol ContentPresenting {
    func presentLoading(
        from viewController: UIViewController
    )

    func dismissLoading()

    func presentStickyBanner(
        content: SDKBannerContent,
        from viewController: UIViewController
    )

    func dismissStickyBanner()

    func present(
        action: SDKAction,
        from viewController: UIViewController
    ) throws
}

extension ContentPresenting {
    func presentLoading(
        from viewController: UIViewController
    ) {}

    func dismissLoading() {}

    func presentStickyBanner(
        content: SDKBannerContent,
        from viewController: UIViewController
    ) {}

    func dismissStickyBanner() {}
}
