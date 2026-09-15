import UIKit
import XCTest
@testable import ZeyWinSDK

@MainActor
final class HostedOfferPresentationTests: XCTestCase {

    func testOfferIsVisibleAboveExistingFullScreenHostModalAndDismissesCleanly() async throws {
        let hostWindow = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .windows
                .first {
                    $0.rootViewController?.view.accessibilityIdentifier
                        == "ZeyWinSDKTestHostRoot"
                },
            "Hosted test app must have its foreground scene window"
        )
        let host = try XCTUnwrap(hostWindow.rootViewController)
        let initialWindowCount = hostWindow.windowScene?.windows.count

        XCTAssertTrue(host.view.window === hostWindow)

        let hostModal = UIViewController()

        hostModal.modalPresentationStyle = .fullScreen
        hostModal.view.backgroundColor = .systemBlue
        host.present(hostModal, animated: false)

        let hostModalIsVisible = await waitUntil {
            host.presentedViewController === hostModal
                && hostModal.viewIfLoaded?.window === hostWindow
        }
        XCTAssertTrue(hostModalIsVisible, "The host modal did not become visible")
        guard hostModalIsVisible else {
            return
        }

        let presenter = ContentPresenter()
        let offerURL = URL(string: "https://offers.example/hosted-modal")!
        let closeExpectation = expectation(description: "Offer close callback")
        var closeCount = 0

        try presenter.present(
            action: .offer(offerURL),
            from: host,
            onClose: {
                closeCount += 1
                closeExpectation.fulfill()
            }
        )

        let offerIsPresentedAboveHostModal = await waitUntil {
            hostModal.presentedViewController is SDKWebViewController
        }
        XCTAssertTrue(
            offerIsPresentedAboveHostModal,
            "The offer was not presented above the full-screen host modal"
        )
        guard offerIsPresentedAboveHostModal else {
            return
        }

        let offerController = try XCTUnwrap(
            hostModal.presentedViewController as? SDKWebViewController
        )

        let offerIsAttachedToVisibleScene = await waitUntil {
            offerController.viewIfLoaded?.window != nil
                && offerController.transitionCoordinator == nil
        }
        XCTAssertTrue(
            offerIsAttachedToVisibleScene,
            "The offer controller never completed presentation into a window"
        )
        guard offerIsAttachedToVisibleScene else {
            return
        }

        let offerWindow = try XCTUnwrap(offerController.view.window)

        XCTAssertTrue(offerWindow.windowScene === hostWindow.windowScene)
        XCTAssertFalse(offerController.view.isHidden)
        XCTAssertGreaterThan(offerController.view.alpha, 0)
        XCTAssertTrue(topmostPresentedController(from: host) === offerController)
        XCTAssertEqual(hostWindow.windowScene?.windows.count, initialWindowCount)

        offerController.dismiss(animated: false)

        await fulfillment(of: [closeExpectation], timeout: 5)

        XCTAssertEqual(closeCount, 1)
        XCTAssertTrue(host.presentedViewController === hostModal)
        XCTAssertNil(hostModal.presentedViewController)

        let offerIsDetached = await waitUntil {
            offerController.view.window == nil
        }
        XCTAssertTrue(
            offerIsDetached,
            "Dismissed offer must be detached from UIKit's window hierarchy"
        )
        XCTAssertEqual(hostWindow.windowScene?.windows.count, initialWindowCount)

        host.dismiss(animated: false)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        return condition()
    }

    private func topmostPresentedController(
        from root: UIViewController
    ) -> UIViewController {
        var controller = root

        while let presentedController = controller.presentedViewController {
            controller = presentedController
        }

        return controller
    }
}
