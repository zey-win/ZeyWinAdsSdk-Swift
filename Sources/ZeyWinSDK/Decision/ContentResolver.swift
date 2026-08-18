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

            registerTracking(
                from: response,
                for: url
            )

            return .offer(url)

        case "internal_ad":
            guard
                let value = response.url,
                let url = URL(string: value)
            else {
                throw SDKError.invalidURL
            }

            registerTracking(
                from: response,
                for: url
            )

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
                    body: response.adBody ?? response.adText,
                    mediaURL: makeURL(response.mediaURL),
                    targetURL: url,
                    ctaText: response.ctaText ?? "Open",
                    tracking: makeTracking(
                        from: response
                    )
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

            let url = try resolvePrimaryURL(
                response: response
            )

            registerTracking(
                from: response,
                for: url
            )

            return .offer(url)

        case .banner,
             .native:

            return .banner(
                SDKBannerContent(
                    title: response.ctaText ?? response.adText ?? response.title ?? "Open",
                    body: response.adBody ?? response.adText,
                    mediaURL: makeURL(response.mediaURL),
                    targetURL: try resolveDestinationURL(
                        response: response
                    ),
                    ctaText: response.ctaText ?? "Open",
                    tracking: makeTracking(
                        from: response
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

    private func resolveDestinationURL(
        response: SDKInitResponse
    ) throws -> URL {
        let value = response.clickURL
            ?? response.storeURL
            ?? response.url
            ?? response.mediaURL

        guard
            let value,
            let url = URL(string: value)
        else {
            throw SDKError.invalidURL
        }

        return url
    }

    private func makeTracking(
        from response: SDKInitResponse
    ) -> SDKAdTracking? {
        let tracking = SDKAdTracking(
            adId: response.adId,
            adType: response.adType?.rawValue ?? response.action,
            impressionURL: makeURL(response.impressionURL),
            clickURL: makeURL(response.clickTrackingURL),
            completeURL: makeURL(response.completeURL),
            rewardURL: makeURL(response.rewardURL)
        )

        return tracking.isEmpty ? nil : tracking
    }

    private func registerTracking(
        from response: SDKInitResponse,
        for url: URL
    ) {
        guard let tracking = makeTracking(from: response) else {
            return
        }

        SDKTrackingRegistry.shared.register(
            tracking: tracking,
            for: url
        )
    }

    private func makeURL(
        _ value: String?
    ) -> URL? {
        guard let value else {
            return nil
        }

        return URL(string: value)
    }
}
