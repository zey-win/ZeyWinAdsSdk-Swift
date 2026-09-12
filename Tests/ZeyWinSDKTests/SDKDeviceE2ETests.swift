import UIKit
import XCTest
@testable import ZeyWinSDK

@MainActor
final class SDKDeviceE2ETests: XCTestCase {

    private var defaults: UserDefaults?
    private var defaultsSuiteName: String?

    override func tearDown() {
        if let defaultsSuiteName {
            defaults?.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil

        super.tearDown()
    }

    func testReferralOfferFlowsThroughLoaderPresentationAndDeliveryWithoutAutopresentation() async {
        let firstOfferURL = URL(string: "https://offers.example/first")!
        let bannerURL = URL(string: "https://offers.example/banner")!
        let client = ScriptedAPIClient(
            referrals: [
                SDKReferralResponse(
                    hasReferral: true,
                    offerURL: firstOfferURL.absoluteString,
                    clickId: "click-first"
                ),
                SDKReferralResponse(
                    hasReferral: false,
                    offerURL: nil,
                    clickId: nil
                )
            ],
            fetchHandler: { request in
                XCTAssertEqual(request.adType, .native)
                return SDKInitResponse(
                    action: "banner",
                    adType: .native,
                    clickURL: bannerURL.absoluteString,
                    ctaText: "Open"
                )
            }
        )
        let presenter = RecordingPresenter()
        let store = makePromotionURLStore()
        let sdk = makeSDK(
            client: client,
            presenter: presenter,
            promotionURLStore: store
        )
        let host = UIViewController()

        sdk.initialize(apiKey: "e2e-key", mode: .mock(.nothing), debugLogging: false)

        let firstResult = await sdk.start(from: host)

        assertSuccess(firstResult, equals: .offer(firstOfferURL))
        XCTAssertEqual(presenter.events, [.loading, .action(.offer(firstOfferURL))])
        XCTAssertEqual(client.deliveredClickIDs, ["click-first"])
        XCTAssertEqual(
            store.storedURL(for: promotionScope),
            firstOfferURL
        )

        presenter.events.removeAll()

        let secondResult = await sdk.start(from: host)

        guard case .success(.banner) = secondResult else {
            return XCTFail("A stored URL must not present an offer without a new referral signal: \(secondResult)")
        }
        XCTAssertEqual(presenter.events.first, .loading)
        XCTAssertFalse(
            presenter.events.contains { event in
                if case .action(.offer) = event {
                    return true
                }
                return false
            }
        )
        XCTAssertEqual(store.storedURL(for: promotionScope), firstOfferURL)
    }

    func testShowInterstitialPresentsInternalAdWithResolvedClickTarget() async {
        let mediaURL = URL(string: "https://creative.example/interstitial.html")!
        let clickURL = URL(string: "https://offers.example/after-click")!
        let client = ScriptedAPIClient(
            fetchHandler: { request in
                XCTAssertEqual(request.adType, .interstitial)
                return SDKInitResponse(
                    action: "interstitial",
                    adType: .interstitial,
                    mediaType: "html",
                    mediaURL: mediaURL.absoluteString,
                    clickURL: clickURL.absoluteString
                )
            }
        )
        let presenter = RecordingPresenter()
        let sdk = makeSDK(client: client, presenter: presenter)

        sdk.initialize(apiKey: "e2e-key", mode: .mock(.nothing), debugLogging: false)

        let result = await sdk.showInterstitial(from: UIViewController())

        let expectedContent = SDKFullscreenAdContent(
            mediaURL: mediaURL,
            mediaType: "html",
            targetURL: clickURL
        )
        assertSuccess(result, equals: .internalAd(expectedContent))
        XCTAssertEqual(presenter.events, [.action(.internalAd(expectedContent))])
        XCTAssertEqual(client.requestedAdTypes, [.interstitial])
    }

    func testBannerCTATapForwardsOriginalBackendClickURL() throws {
        let clickURL = try XCTUnwrap(
            URL(string: "https://clicks.example/referral/click-123?source=banner")
        )
        var openedURL: URL?
        let banner = SDKBannerView(
            content: SDKBannerContent(
                title: "Open",
                targetURL: clickURL
            ),
            onClick: { url in
                openedURL = url
            }
        )

        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
        }

        host.view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            banner.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
            banner.heightAnchor.constraint(equalToConstant: 38)
        ])
        host.view.layoutIfNeeded()

        let tapSelector = NSSelectorFromString("handleTap")
        XCTAssertTrue(banner.responds(to: tapSelector))
        _ = banner.perform(tapSelector)

        XCTAssertEqual(openedURL, clickURL)
    }

    func testContentPresenterRoutesOfferToWebViewWithOriginalURL() throws {
        let offerURL = URL(string: "https://offers.example/original")!
        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
        }

        let presenter = ContentPresenter()

        try presenter.present(
            action: .offer(offerURL),
            from: host,
            onClose: nil
        )

        let webViewController = try XCTUnwrap(
            host.presentedViewController as? SDKWebViewController
        )
        XCTAssertEqual(webViewController.webView.url, offerURL)
    }

    func testBlockedDeviceUsesInternalAdFallback() async {
        let mediaURL = URL(string: "https://creative.example/fallback.html")!
        let client = ScriptedAPIClient(
            deviceReport: SDKDeviceReportResponse(
                sdkStatus: "blocked",
                blockReason: "policy"
            ),
            fetchHandler: { request in
                XCTAssertEqual(request.adType, .interstitial)
                return SDKInitResponse(
                    action: "interstitial",
                    adType: .interstitial,
                    mediaURL: mediaURL.absoluteString
                )
            }
        )
        let presenter = RecordingPresenter()
        let sdk = makeSDK(client: client, presenter: presenter)

        sdk.initialize(apiKey: "e2e-key", mode: .mock(.nothing), debugLogging: false)

        let result = await sdk.start(from: UIViewController())
        let expected = SDKAction.internalAd(
            SDKFullscreenAdContent(mediaURL: mediaURL)
        )

        assertSuccess(result, equals: expected)
        XCTAssertEqual(presenter.events, [.loading, .action(expected)])
        XCTAssertEqual(client.requestedAdTypes, [.interstitial])
    }

    func testBlockedDeviceWithoutCreativeReturnsBlockedWithoutPresentation() async {
        let client = ScriptedAPIClient(
            deviceReport: SDKDeviceReportResponse(
                sdkStatus: "blocked",
                blockReason: "policy"
            ),
            fetchHandler: { request in
                XCTAssertTrue(
                    [.interstitial, .native, .banner].contains(request.adType)
                )
                return SDKInitResponse(action: "none")
            }
        )
        let presenter = RecordingPresenter()
        let sdk = makeSDK(client: client, presenter: presenter)

        sdk.initialize(apiKey: "e2e-key", mode: .mock(.nothing), debugLogging: false)

        let result = await sdk.start(from: UIViewController())

        assertSuccess(result, equals: .blocked(reason: "policy"))
        XCTAssertEqual(presenter.events, [.loading, .dismissLoading])
        XCTAssertEqual(client.requestedAdTypes, [.interstitial, .native, .banner])
    }

    func testInvalidReferralURLFallsBackWithoutPresentingOffer() async {
        let client = ScriptedAPIClient(
            referrals: [
                SDKReferralResponse(
                    hasReferral: true,
                    offerURL: "not a valid URL",
                    clickId: "invalid-click"
                )
            ],
            fetchHandler: { request in
                XCTAssertEqual(request.adType, .native)
                return SDKInitResponse(
                    action: "banner",
                    adType: .native,
                    clickURL: "https://offers.example/banner"
                )
            }
        )
        let presenter = RecordingPresenter()
        let sdk = makeSDK(client: client, presenter: presenter)

        sdk.initialize(apiKey: "e2e-key", mode: .mock(.nothing), debugLogging: false)

        let result = await sdk.start(from: UIViewController())

        guard case .success(.banner) = result else {
            return XCTFail("Expected fallback banner after invalid referral URL, got \(result)")
        }
        XCTAssertFalse(
            presenter.events.contains { event in
                if case .action(.offer) = event {
                    return true
                }
                return false
            }
        )
        XCTAssertTrue(client.deliveredClickIDs.isEmpty)
    }

    func testMissingCreativeAndNetworkFailureDoNotPresentFullscreenAd() async {
        let missingCreativeClient = ScriptedAPIClient(
            fetchHandler: { _ in
                SDKInitResponse(action: "internal_ad")
            }
        )
        let missingCreativePresenter = RecordingPresenter()
        let missingCreativeSDK = makeSDK(
            client: missingCreativeClient,
            presenter: missingCreativePresenter
        )
        missingCreativeSDK.initialize(apiKey: "e2e-key", mode: .mock(.nothing), debugLogging: false)

        let missingCreativeResult = await missingCreativeSDK.showInterstitial(
            from: UIViewController()
        )

        assertFailure(missingCreativeResult, matches: .invalidURL)
        XCTAssertTrue(missingCreativePresenter.events.isEmpty)

        let networkClient = ScriptedAPIClient(
            fetchHandler: { _ in
                throw SDKError.network(URLError(.notConnectedToInternet))
            }
        )
        let networkPresenter = RecordingPresenter()
        let networkSDK = makeSDK(client: networkClient, presenter: networkPresenter)
        networkSDK.initialize(apiKey: "e2e-key", mode: .mock(.nothing), debugLogging: false)

        let networkResult = await networkSDK.showInterstitial(from: UIViewController())

        guard case .failure(.network) = networkResult else {
            return XCTFail("Expected a network failure, got \(networkResult)")
        }
        XCTAssertTrue(networkPresenter.events.isEmpty)
    }

    func testWebViewLoadFailureDoesNotCloseOffer() {
        var closeCount = 0
        let controller = SDKWebViewController(
            url: URL(string: "https://invalid.example/offer")!,
            tracking: nil,
            onClose: {
                closeCount += 1
            }
        )
        controller.loadViewIfNeeded()

        controller.webView(
            controller.webView,
            didFailProvisionalNavigation: nil,
            withError: URLError(.cannotConnectToHost)
        )

        XCTAssertEqual(closeCount, 0)
    }

    private var promotionScope: PromotionURLScope {
        PromotionURLScope(
            bundleIdentifier: deviceInfo.bundleId,
            apiKey: "e2e-key"
        )
    }

    private var deviceInfo: DeviceInfo {
        DeviceInfo(
            bundleId: "com.zeywin.e2e",
            appVersion: "1",
            deviceModel: "iPhone",
            osName: "iOS",
            osVersion: "18",
            locale: "en_US",
            timezone: "UTC",
            language: "en",
            country: "US",
            deviceId: "e2e-device"
        )
    }

    private func makeSDK(
        client: ScriptedAPIClient,
        presenter: RecordingPresenter,
        promotionURLStore: PromotionURLStore? = nil
    ) -> ZeyWinSDK {
        ZeyWinSDK(
            deviceInfoProvider: StaticDeviceInfoProvider(deviceInfo: deviceInfo),
            presenter: presenter,
            promotionURLStore: promotionURLStore ?? makePromotionURLStore(),
            apiClientFactory: { _ in client }
        )
    }

    private func makePromotionURLStore() -> PromotionURLStore {
        let suiteName = "ZeyWinSDKTests.DeviceE2E.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        self.defaults = defaults
        defaultsSuiteName = suiteName

        return PromotionURLStore(defaults: defaults)
    }

    private func assertSuccess(
        _ result: Result<SDKAction, SDKError>,
        equals expected: SDKAction,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .success(action) = result else {
            return XCTFail("Expected success(\(expected)), got \(result)", file: file, line: line)
        }
        XCTAssertEqual(action, expected, file: file, line: line)
    }

    private func assertFailure(
        _ result: Result<SDKAction, SDKError>,
        matches expected: SDKError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .failure(error) = result else {
            return XCTFail("Expected failure(\(expected)), got \(result)", file: file, line: line)
        }
        XCTAssertEqual(error.localizedDescription, expected.localizedDescription, file: file, line: line)
    }
}

private final class StaticDeviceInfoProvider: DeviceInfoProviding {
    private let deviceInfo: DeviceInfo

    init(deviceInfo: DeviceInfo) {
        self.deviceInfo = deviceInfo
    }

    func collect() -> DeviceInfo {
        deviceInfo
    }
}

@MainActor
private final class RecordingPresenter: ContentPresenting {

    enum Event: Equatable {
        case loading
        case dismissLoading
        case action(SDKAction)
    }

    var events: [Event] = []

    func presentLoading(from viewController: UIViewController) {
        events.append(.loading)
    }

    func dismissLoading() {
        events.append(.dismissLoading)
    }

    func dismissLoading(completion: @escaping () -> Void) {
        events.append(.dismissLoading)
        completion()
    }

    func present(
        action: SDKAction,
        from viewController: UIViewController,
        onClose: (() -> Void)?
    ) throws {
        events.append(.action(action))
    }
}

private final class ScriptedAPIClient: APIClientProtocol {

    var referrals: [SDKReferralResponse]
    var deviceReport: SDKDeviceReportResponse
    var fetchHandler: (SDKInitRequest) throws -> SDKInitResponse
    var requestedAdTypes: [SDKAdType] = []
    var deliveredClickIDs: [String?] = []

    init(
        referrals: [SDKReferralResponse] = [
            SDKReferralResponse(hasReferral: false, offerURL: nil, clickId: nil)
        ],
        deviceReport: SDKDeviceReportResponse = SDKDeviceReportResponse(sdkStatus: "active"),
        fetchHandler: @escaping (SDKInitRequest) throws -> SDKInitResponse
    ) {
        self.referrals = referrals
        self.deviceReport = deviceReport
        self.fetchHandler = fetchHandler
    }

    func reportDevice(request: SDKDeviceReportRequest) async throws -> SDKDeviceReportResponse {
        deviceReport
    }

    func fetchInitialConfiguration(request: SDKInitRequest) async throws -> SDKInitResponse {
        requestedAdTypes.append(request.adType)
        return try fetchHandler(request)
    }

    func fetchGeo() async throws -> SDKGeoResponse {
        SDKGeoResponse(country: nil)
    }

    func checkReferral(request: SDKReferralCheckRequest) async throws -> SDKReferralResponse {
        guard !referrals.isEmpty else {
            return SDKReferralResponse(hasReferral: false, offerURL: nil, clickId: nil)
        }

        return referrals.removeFirst()
    }

    func checkReferralByClick(
        request: SDKReferralCheckByClickRequest
    ) async throws -> SDKReferralResponse {
        SDKReferralResponse(hasReferral: false, offerURL: nil, clickId: nil)
    }

    func markReferralDelivered(request: SDKReferralDeliveredRequest) async {
        deliveredClickIDs.append(request.clickId)
    }

    func trackEvent(request: SDKEventRequest) async {}

    func trackWebView(request: SDKWebViewEventRequest) async {}
}
