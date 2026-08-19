protocol APIClientProtocol {
    func reportDevice(
        request: SDKDeviceReportRequest
    ) async throws -> SDKDeviceReportResponse

    func fetchInitialConfiguration(
        request: SDKInitRequest
    ) async throws -> SDKInitResponse

    func checkReferral(
        request: SDKReferralCheckRequest
    ) async throws -> SDKReferralResponse

    func checkReferralByClick(
        request: SDKReferralCheckByClickRequest
    ) async throws -> SDKReferralResponse

    func markReferralDelivered(
        request: SDKReferralDeliveredRequest
    ) async

    func fetchGeo() async throws -> SDKGeoResponse

    func trackEvent(
        request: SDKEventRequest
    ) async

    func trackWebView(
        request: SDKWebViewEventRequest
    ) async
}
