protocol APIClientProtocol {
    func fetchInitialConfiguration(
        request: SDKInitRequest
    ) async throws -> SDKInitResponse
}
