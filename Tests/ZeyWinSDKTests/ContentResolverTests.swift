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

        guard case let .banner(content) = action else {
            return XCTFail("Expected a banner action, got \(action)")
        }

        XCTAssertEqual(content.title, "Test")
        XCTAssertEqual(content.targetURL, URL(string: "https://example.com")!)
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

        guard case let .internalAd(content) = action else {
            return XCTFail("Expected an internal ad action, got \(action)")
        }

        XCTAssertEqual(content.mediaURL, URL(string: "https://example.com/ad.html")!)
        XCTAssertEqual(content.targetURL, URL(string: "https://example.com/click")!)
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

        guard case let .banner(content) = action else {
            return XCTFail("Expected a banner action, got \(action)")
        }

        XCTAssertEqual(content.title, "Install")
        XCTAssertEqual(content.targetURL, URL(string: "https://example.com/click")!)
        XCTAssertEqual(content.ctaText, "Install")
    }

    func testUnityBannerResponsePrefersClickURLOverStoreURL() throws {
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

        guard case let .banner(content) = action else {
            return XCTFail("Expected a banner action, got \(action)")
        }

        XCTAssertEqual(content.targetURL, URL(string: "https://example.com/offer")!)
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

        guard case let .banner(content) = action else {
            return XCTFail("Expected a banner action, got \(action)")
        }

        XCTAssertEqual(content.title, "Title")
        XCTAssertEqual(content.body, "Body")
        XCTAssertEqual(content.mediaURL, URL(string: "https://example.com/image.png")!)
        XCTAssertEqual(content.targetURL, URL(string: "https://example.com/click")!)
        XCTAssertEqual(content.ctaText, "Install")
        XCTAssertEqual(
            content.tracking,
            SDKAdTracking(
                adType: "banner",
                impressionURL: URL(string: "https://example.com/impression")!,
                clickURL: URL(string: "https://example.com/click-track")!
            )
        )
    }
    func testBannerResponsePreservesPromoPopupFields() throws {
        let response = SDKInitResponse(
            action: "banner",
            adType: .banner,
            clickURL: "https://example.com/click",
            adText: "Promo",
            adBody: "Win today",
            ctaText: "Play",
            ctaText2: "More",
            popupDelaySec: 30,
            popupRepeatSec: 120
        )

        let action = try resolver.resolve(
            response: response
        )

        XCTAssertEqual(
            action,
            .banner(
                SDKBannerContent(
                    title: "Promo",
                    body: "Win today",
                    targetURL: URL(string: "https://example.com/click")!,
                    ctaText: "Play",
                    secondaryCTAText: "More",
                    popupDelaySec: 30,
                    popupRepeatSec: 120
                )
            )
        )
    }

}
