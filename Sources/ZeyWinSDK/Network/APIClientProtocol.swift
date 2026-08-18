protocol APIClientProtocol {
    func reportDevice(
        request: SDKDeviceReportRequest
    ) async throws -> SDKDeviceReportResponse

    func fetchInitialConfiguration(
        request: SDKInitRequest
    ) async throws -> SDKInitResponse

    func trackEvent(
        request: SDKEventRequest
    ) async
}
