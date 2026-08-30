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
            let url = try resolvePrimaryURL(
                response: response
            )

            registerTracking(
                from: response,
                for: url
            )

            return .offer(url)

        case "internal_ad":
            let content = SDKFullscreenAdContent(
                mediaURL: try resolveCreativeURL(response: response),
                targetURL: resolveOptionalDestinationURL(response: response),
                durationSec: response.durationSec,
                skipAfterSec: response.skipAfterSec,
                tracking: makeTracking(from: response)
            )

            registerTracking(
                from: response,
                for: content.mediaURL
            )

            return .internalAd(content)

        case "banner":
            return .banner(
                SDKBannerContent(
                    title: localizedBannerTitle(response.adText ?? response.title ?? response.ctaText),
                    body: localizedBannerBody(response.adBody),
                    iconURL: makeURL(response.iconURL),
                    mediaURL: makeURL(response.mediaURL),
                    targetURL: try resolveDestinationURL(
                        response: response
                    ),
                    ctaText: localizedPrimaryCTA(response.ctaText),
                    secondaryCTAText: localizedSecondaryCTA(response.ctaText2),
                    popupDelaySec: response.popupDelaySec,
                    popupRepeatSec: response.popupRepeatSec,
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

            let content = SDKFullscreenAdContent(
                mediaURL: try resolveCreativeURL(response: response),
                targetURL: resolveOptionalDestinationURL(response: response),
                durationSec: response.durationSec,
                skipAfterSec: response.skipAfterSec,
                tracking: makeTracking(from: response)
            )

            registerTracking(
                from: response,
                for: content.mediaURL
            )

            return .internalAd(content)

        case .banner,
             .native:

            return .banner(
                SDKBannerContent(
                    title: localizedBannerTitle(response.adText ?? response.title ?? response.ctaText),
                    body: localizedBannerBody(response.adBody),
                    iconURL: makeURL(response.iconURL),
                    mediaURL: makeURL(response.mediaURL),
                    targetURL: try resolveDestinationURL(
                        response: response
                    ),
                    ctaText: localizedPrimaryCTA(response.ctaText),
                    secondaryCTAText: localizedSecondaryCTA(response.ctaText2),
                    popupDelaySec: response.popupDelaySec,
                    popupRepeatSec: response.popupRepeatSec,
                    tracking: makeTracking(
                        from: response
                    )
                )
            )
        }
    }

    private func localizedBannerTitle(_ value: String?) -> String {
        localized(
            value,
            englishDefaults: [
                "try your luck — play plinko!",
                "try your luck - play plinko!",
                "open"
            ],
            fallback: [
                "ru": "Попробуйте удачу — играйте в Плинко!",
                "en": "Try your luck — play Plinko!",
                "es": "Prueba tu suerte — juega Plinko!",
                "de": "Versuche dein Glück — spiele Plinko!",
                "fr": "Tentez votre chance — jouez à Plinko!",
                "it": "Tenta la fortuna — gioca a Plinko!",
                "pt": "Tente a sorte — jogue Plinko!",
                "tr": "Şansını dene — Plinko oyna!",
                "ar": "جرّب حظك — العب بلينكو!",
                "hi": "अपनी किस्मत आज़माएं — Plinko खेलें!",
                "id": "Coba keberuntunganmu — main Plinko!",
                "vi": "Thử vận may — chơi Plinko!",
                "th": "ลองเสี่ยงโชค — เล่น Plinko!"
            ]
        )
    }

    private func localizedBannerBody(_ value: String?) -> String? {
        localized(
            value,
            englishDefaults: [
                "drop the ball and see where it lands. start playing now!",
                "play and win today"
            ],
            fallback: [
                "ru": "Заберите призы и испытайте удачу прямо сейчас!",
                "en": "Drop the ball and see where it lands. Start playing now!",
                "es": "Suelta la bola y prueba tu suerte ahora!",
                "de": "Lass die Kugel fallen und spiele jetzt!",
                "fr": "Lancez la bille et tentez votre chance maintenant!",
                "it": "Lascia cadere la pallina e gioca subito!",
                "pt": "Solte a bola e teste sua sorte agora!",
                "tr": "Topu bırak ve hemen şansını dene!",
                "ar": "أسقط الكرة وجرّب حظك الآن!",
                "hi": "गेंद गिराएं और अभी अपनी किस्मत आज़माएं!",
                "id": "Jatuhkan bola dan coba keberuntunganmu sekarang!",
                "vi": "Thả bóng và thử vận may ngay!",
                "th": "ปล่อยลูกบอลแล้วลองเสี่ยงโชคตอนนี้!"
            ]
        )
    }

    private func localizedPrimaryCTA(_ value: String?) -> String {
        localized(
            value,
            englishDefaults: ["play now", "open"],
            fallback: [
                "ru": "Играть сейчас",
                "en": "Play Now",
                "es": "Jugar ahora",
                "de": "Jetzt spielen",
                "fr": "Jouer",
                "it": "Gioca ora",
                "pt": "Jogar agora",
                "tr": "Şimdi oyna",
                "ar": "العب الآن",
                "hi": "अभी खेलें",
                "id": "Main Sekarang",
                "vi": "Chơi ngay",
                "th": "เล่นเลย"
            ]
        )
    }

    private func localizedSecondaryCTA(_ value: String?) -> String? {
        localized(
            value,
            englishDefaults: ["learn more"],
            fallback: [
                "ru": "Узнать подробнее",
                "en": "Learn more",
                "es": "Más información",
                "de": "Mehr erfahren",
                "fr": "En savoir plus",
                "it": "Scopri di più",
                "pt": "Saiba mais",
                "tr": "Daha fazla",
                "ar": "اعرف المزيد",
                "hi": "और जानें",
                "id": "Pelajari",
                "vi": "Tìm hiểu thêm",
                "th": "ดูเพิ่มเติม"
            ]
        )
    }

    private func localized(
        _ value: String?,
        englishDefaults: Set<String>,
        fallback: [String: String]
    ) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalized?.lowercased()

        if let normalized, !normalized.isEmpty, lowercased.map({ !englishDefaults.contains($0) }) == true {
            return normalized
        }

        let language = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).languageCode }
            ?? Locale.current.languageCode
            ?? "en"

        return fallback[language] ?? fallback["en"] ?? normalized ?? ""
    }

    private func resolvePrimaryURL(
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

    private func resolveCreativeURL(
        response: SDKInitResponse
    ) throws -> URL {
        let value = response.mediaURL
            ?? response.url
            ?? response.storeURL
            ?? response.clickURL

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
        let value = response.storeURL
            ?? response.clickURL
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

    private func resolveOptionalDestinationURL(
        response: SDKInitResponse
    ) -> URL? {
        let value = response.storeURL
            ?? response.clickURL
            ?? response.url

        guard let value else {
            return nil
        }

        return URL(string: value)
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
