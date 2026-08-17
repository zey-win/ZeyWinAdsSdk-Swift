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
}
