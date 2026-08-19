import Foundation

final class MockAPIClient: APIClientProtocol {

    private let scenario: MockScenario

    init(scenario: MockScenario) {
        self.scenario = scenario
    }

    func reportDevice(
        request: SDKDeviceReportRequest
    ) async throws -> SDKDeviceReportResponse {
        SDKDeviceReportResponse(
            sdkStatus: "active",
            blockReason: "mock"
        )
    }

    func fetchInitialConfiguration(
        request: SDKInitRequest
    ) async throws -> SDKInitResponse {

        try await Task.sleep(
            nanoseconds: 350_000_000
        )

        switch scenario {
        case .offer:
            return SDKInitResponse(
                action: "offer",
                url: "https://example.com"
            )

        case .internalAd:
            return SDKInitResponse(
                action: "internal_ad",
                url: "https://www.apple.com/app-store/"
            )

        case .banner:
            return SDKInitResponse(
                action: "banner",
                url: "https://example.com",
                title: "Mock banner"
            )

        case .blocked:
            return SDKInitResponse(
                action: "blocked",
                reason: "mock_block_reason"
            )

        case .nothing:
            return SDKInitResponse(
                action: "none"
            )

        case .networkError:
            throw SDKError.network(
                URLError(.notConnectedToInternet)
            )
        }
    }

    func fetchGeo() async throws -> SDKGeoResponse {
        SDKGeoResponse(
            country: "US"
        )
    }

    func checkReferral(
        request: SDKReferralCheckRequest
    ) async throws -> SDKReferralResponse {
        SDKReferralResponse(
            hasReferral: false,
            offerURL: nil,
            clickId: nil
        )
    }

    func checkReferralByClick(
        request: SDKReferralCheckByClickRequest
    ) async throws -> SDKReferralResponse {
        SDKReferralResponse(
            hasReferral: false,
            offerURL: nil,
            clickId: nil
        )
    }

    func markReferralDelivered(
        request: SDKReferralDeliveredRequest
    ) async {}

    func trackEvent(
        request: SDKEventRequest
    ) async {}

    func trackWebView(
        request: SDKWebViewEventRequest
    ) async {}
}
