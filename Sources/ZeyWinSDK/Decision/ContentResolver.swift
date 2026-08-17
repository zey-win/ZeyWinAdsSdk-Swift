import Foundation

final class ContentResolver: ContentResolving {

    func resolve(
        response: SDKInitResponse
    ) throws -> SDKAction {

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
}
