protocol ContentResolving {
    func resolve(
        response: SDKInitResponse
    ) throws -> SDKAction
}
