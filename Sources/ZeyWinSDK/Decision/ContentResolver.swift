import Foundation

final class ContentResolver: ContentResolving {

    func resolve(
        response: SDKInitResponse
    ) throws -> SDKAction {

        if let adType = response.adType {
            return try resolveAdResponse(
                response: response,
                adType: adType
            )
        }

        switch response.action.lowercased() {

        case "offer":
            guard
                let value = response.url,
                let url = URL(string: value)
            else {
                throw SDKError.invalidURL
            }

            return .offer(url)

        case "internal_ad":
            guard
                let value = response.url,
                let url = URL(string: value)
            else {
                throw SDKError.invalidURL
            }

            return .internalAd(url)

        case "banner":
            guard
                let value = response.url,
                let url = URL(string: value)
            else {
                throw SDKError.invalidURL
            }

            return .banner(
                SDKBannerContent(
                    title: response.title ?? "Open",
                    targetURL: url
                )
            )

        case "blocked":
            return .blocked(
                reason: response.reason
            )

        case "none":
            return .none

        default:
            throw SDKError.unsupportedAction(
                response.action
            )
        }
    }

    private func resolveAdResponse(
        response: SDKInitResponse,
        adType: SDKAdType
    ) throws -> SDKAction {
        switch adType {
        case .interstitial,
             .rewarded,
             .popup:

            return .offer(
                try resolvePrimaryURL(
                    response: response
                )
            )

        case .banner,
             .native:

            return .banner(
                SDKBannerContent(
                    title: response.ctaText ?? response.adText ?? response.title ?? "Open",
                    targetURL: try resolvePrimaryURL(
                        response: response
                    )
                )
            )
        }
    }

    private func resolvePrimaryURL(
        response: SDKInitResponse
    ) throws -> URL {
        let value = response.mediaURL
            ?? response.clickURL
            ?? response.storeURL
            ?? response.url

        guard
            let value,
            let url = URL(string: value)
        else {
            throw SDKError.invalidURL
        }

        return url
    }
}
