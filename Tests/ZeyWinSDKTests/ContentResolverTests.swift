import XCTest
@testable import ZeyWinSDK

final class ContentResolverTests: XCTestCase {

    private let resolver = ContentResolver()

    func testOfferResponse() throws {
        let response = SDKInitResponse(
            action: "offer",
            url: "https://example.com"
        )

        let action = try resolver.resolve(
            response: response
        )

        XCTAssertEqual(
            action,
            .offer(
                URL(string: "https://example.com")!
            )
        )
    }

    func testBannerResponse() throws {
        let response = SDKInitResponse(
            action: "banner",
            url: "https://example.com",
            title: "Test"
        )

        let action = try resolver.resolve(
            response: response
        )

        XCTAssertEqual(
            action,
            .banner(
                SDKBannerContent(
                    title: "Test",
                    targetURL: URL(string: "https://example.com")!
                )
            )
        )
    }

    func testBlockedResponse() throws {
        let response = SDKInitResponse(
            action: "blocked",
            reason: "test"
        )

        let action = try resolver.resolve(
            response: response
        )

        XCTAssertEqual(
            action,
            .blocked(reason: "test")
        )
    }

    func testUnknownActionThrows() {
        let response = SDKInitResponse(
            action: "unknown_action"
        )

        XCTAssertThrowsError(
            try resolver.resolve(
                response: response
            )
        )
    }

    func testUnityInterstitialResponseResolvesToInternalAd() throws {
        let response = SDKInitResponse(
            action: "interstitial",
            adType: .interstitial,
            mediaType: "html",
            mediaURL: "https://example.com/ad.html",
            clickURL: "https://example.com/click"
        )

        let action = try resolver.resolve(
            response: response
        )

        XCTAssertEqual(
            action,
            .internalAd(
                SDKFullscreenAdContent(
                    mediaURL: URL(string: "https://example.com/ad.html")!,
                    targetURL: URL(string: "https://example.com/click")!
                )
            )
        )
    }

    func testUnityBannerResponseResolvesToBanner() throws {
        let response = SDKInitResponse(
            action: "banner",
            adType: .banner,
            clickURL: "https://example.com/click",
            ctaText: "Install"
        )

        let action = try resolver.resolve(
            response: response
        )

        XCTAssertEqual(
            action,
            .banner(
                SDKBannerContent(
                    title: "Install",
                    targetURL: URL(string: "https://example.com/click")!,
                    ctaText: "Install"
                )
            )
        )
    }

    func testUnityBannerResponsePrefersStoreURLForCrossPromo() throws {
        let response = SDKInitResponse(
            action: "banner",
            adType: .banner,
            clickURL: "https://example.com/offer",
            storeURL: "https://apps.apple.com/app/id123",
            ctaText: "Install"
        )

        let action = try resolver.resolve(
            response: response
        )

        XCTAssertEqual(
            action,
            .banner(
                SDKBannerContent(
                    title: "Install",
                    targetURL: URL(string: "https://apps.apple.com/app/id123")!,
                    ctaText: "Install"
                )
            )
        )
    }

    func testBannerResponsePreservesMediaAndTracking() throws {
        let response = SDKInitResponse(
            action: "banner",
            adType: .banner,
            mediaURL: "https://example.com/image.png",
            clickURL: "https://example.com/click",
            impressionURL: "https://example.com/impression",
            clickTrackingURL: "https://example.com/click-track",
            adText: "Title",
            adBody: "Body",
            ctaText: "Install"
        )

        let action = try resolver.resolve(
            response: response
        )

        XCTAssertEqual(
            action,
            .banner(
                SDKBannerContent(
                    title: "Install",
                    body: "Body",
                    mediaURL: URL(string: "https://example.com/image.png")!,
                    targetURL: URL(string: "https://example.com/click")!,
                    ctaText: "Install",
                    tracking: SDKAdTracking(
                        adType: "banner",
                        impressionURL: URL(string: "https://example.com/impression")!,
                        clickURL: URL(string: "https://example.com/click-track")!
                    )
                )
            )
        )
    }
}
