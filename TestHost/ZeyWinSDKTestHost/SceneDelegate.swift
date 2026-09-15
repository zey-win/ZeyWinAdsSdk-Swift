import UIKit

final class TestHostSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        let rootViewController = UIViewController()

        rootViewController.view.backgroundColor = .systemBackground
        rootViewController.view.accessibilityIdentifier = "ZeyWinSDKTestHostRoot"
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        self.window = window
    }
}
