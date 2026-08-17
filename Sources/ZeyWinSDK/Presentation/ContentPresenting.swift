import UIKit

@MainActor
protocol ContentPresenting {
    func present(
        action: SDKAction,
        from viewController: UIViewController
    ) throws
}
