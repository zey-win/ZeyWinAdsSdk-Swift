protocol ContentResolving {
    func resolve(
        response: SDKInitResponse,
        promotionScope: PromotionURLScope?
    ) throws -> SDKAction
}

extension ContentResolving {
    func resolve(
        response: SDKInitResponse
    ) throws -> SDKAction {
        try resolve(
            response: response,
            promotionScope: nil
        )
    }
}
