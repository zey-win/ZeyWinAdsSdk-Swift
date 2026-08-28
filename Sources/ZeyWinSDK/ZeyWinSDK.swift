import UIKit

@MainActor
public final class ZeyWinSDK {

    public static let shared = ZeyWinSDK()

    public private(set) var state: SDKState = .idle

    private var configuration: SDKConfiguration?
    private var apiClient: APIClientProtocol?

    private let deviceInfoProvider: DeviceInfoProviding
    private let resolver: ContentResolving
    private let presenter: ContentPresenting
    private var fullscreenAdTimer: Timer?

    private init(
        deviceInfoProvider: DeviceInfoProviding = DeviceInfoProvider(),
        resolver: ContentResolving = ContentResolver(),
        presenter: ContentPresenting? = nil
    ) {
        self.deviceInfoProvider = deviceInfoProvider
        self.resolver = resolver
        self.presenter = presenter ?? ContentPresenter()
    }

    public func initialize(
        apiKey: String,
        mode: SDKMode = .mock(.offer),
        productionConfiguration: SDKProductionConfiguration = .default,
        debugLogging: Bool = true
    ) {
        let trimmedKey = apiKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedKey.isEmpty else {
            state = .failed("API key is empty")
            return
        }

        SDKLogger.isEnabled = debugLogging

        state = .initializing

        let configuration = SDKConfiguration(
            apiKey: trimmedKey,
            mode: mode,
            productionConfiguration: productionConfiguration
        )

        self.configuration = configuration

        switch mode {
        case .mock(let scenario):
            self.apiClient = MockAPIClient(
                scenario: scenario
            )

        case .production:
            self.apiClient = RealAPIClient(
                configuration: productionConfiguration
            )
        }

        state = .ready

        SDKLogger.log(
            "SDK initialized"
        )
    }

    @discardableResult
    public func start(
        from viewController: UIViewController
    ) async -> Result<SDKAction, SDKError> {

        guard let configuration else {
            state = .failed(
                "SDK is not initialized"
            )

            return .failure(
                .notInitialized
            )
        }

        guard let apiClient else {
            state = .failed(
                "API client is not configured"
            )

            return .failure(
                .apiClientUnavailable
            )
        }

        guard
            state != .requesting,
            state != .presenting
        else {
            return .failure(
                .alreadyRunning
            )
        }

        presenter.presentLoading(
            from: viewController
        )

        do {
            state = .collectingDeviceInfo

            SDKLogger.log(
                "Collecting device info"
            )

            let deviceInfo = deviceInfoProvider.collect()

            SDKTrackingClient.shared.configure(
                apiClient: apiClient,
                apiKey: configuration.apiKey,
                device: deviceInfo
            )

            let localReport = makeDeviceReport(
                deviceInfo: deviceInfo
            )

            if let referralAction = await resolveReferralIfNeeded(
                configuration: configuration,
                apiClient: apiClient,
                deviceInfo: deviceInfo
            ) {
                state = .presenting

                try presenter.present(
                    action: referralAction.action,
                    from: viewController
                )

                await apiClient.markReferralDelivered(
                    request: SDKReferralDeliveredRequest(
                        apiKey: configuration.apiKey,
                        device: deviceInfo,
                        clickId: referralAction.clickId
                    )
                )

                state = .ready

                return .success(
                    referralAction.action
                )
            }

            do {
                let reportResponse = try await apiClient.reportDevice(
                    request: localReport
                )

                SDKLogger.log(
                    "Device report verdict: \(reportResponse.sdkStatus) \(reportResponse.blockReason ?? "none")"
                )

                if reportResponse.sdkStatus == "blocked" {
                    presenter.dismissLoading()
                    state = .ready

                    return .success(
                        .blocked(reason: reportResponse.blockReason)
                    )
                }
            } catch {
                SDKLogger.log(
                    "Device report failed: \(error.localizedDescription)"
                )

                if localReport.sdkStatus == "blocked" {
                    presenter.dismissLoading()
                    state = .ready

                    return .success(
                        .blocked(reason: localReport.blockReason)
                    )
                }
            }

            await auditGeoIfNeeded(
                apiClient: apiClient,
                deviceInfo: deviceInfo
            )

            if let stickyBanner = await resolveStickyBannerIfAvailable(
                configuration: configuration,
                apiClient: apiClient,
                deviceInfo: deviceInfo
            ) {
                presenter.dismissLoading()
                presenter.presentStickyBanner(
                    content: stickyBanner,
                    from: viewController
                )
                scheduleFullscreenAds(
                    configuration: configuration,
                    apiClient: apiClient,
                    deviceInfo: deviceInfo,
                    from: viewController
                )

                state = .ready

                return .success(
                    .banner(stickyBanner)
                )
            }

            let request = SDKInitRequest(
                apiKey: configuration.apiKey,
                device: deviceInfo,
                adType: .interstitial
            )

            state = .requesting

            SDKLogger.log(
                "Requesting SDK configuration"
            )

            let response = try await apiClient
                .fetchInitialConfiguration(
                    request: request
                )

            let action = try resolver.resolve(
                response: response
            )

            switch action {
            case .none:
                SDKLogger.log(
                    "Backend verdict: none"
                )

                presenter.dismissLoading()
                state = .ready

                return .success(
                    action
                )

            case .blocked(let reason):
                SDKLogger.log(
                    "Backend verdict: blocked(\(reason ?? "unknown"))"
                )

                presenter.dismissLoading()
                state = .ready

                return .success(
                    action
                )

            case .offer,
                 .internalAd,
                 .banner:

                state = .presenting

                try presenter.present(
                    action: action,
                    from: viewController
                )

                state = .ready

                return .success(
                    action
                )
            }

        } catch let error as SDKError {
            presenter.dismissLoading()

            SDKLogger.log(
                "SDK failed: \(error.localizedDescription)"
            )

            state = .failed(
                error.localizedDescription
            )

            return .failure(
                error
            )

        } catch {
            presenter.dismissLoading()

            let sdkError = SDKError.unknown(
                error
            )

            SDKLogger.log(
                "SDK failed: \(sdkError.localizedDescription)"
            )

            state = .failed(
                sdkError.localizedDescription
            )

            return .failure(
                sdkError
            )
        }
    }

    @discardableResult
    public func showRewarded(
        from viewController: UIViewController
    ) async -> Result<SDKAction, SDKError> {
        await showFullscreenAd(
            adType: .rewarded,
            from: viewController
        )
    }

    @discardableResult
    public func showInterstitial(
        from viewController: UIViewController
    ) async -> Result<SDKAction, SDKError> {
        await showFullscreenAd(
            adType: .interstitial,
            from: viewController
        )
    }

    private func showFullscreenAd(
        adType: SDKAdType,
        from viewController: UIViewController
    ) async -> Result<SDKAction, SDKError> {
        guard let configuration else {
            return .failure(.notInitialized)
        }

        guard let apiClient else {
            return .failure(.apiClientUnavailable)
        }

        do {
            let deviceInfo = deviceInfoProvider.collect()

            SDKTrackingClient.shared.configure(
                apiClient: apiClient,
                apiKey: configuration.apiKey,
                device: deviceInfo
            )

            let response = try await apiClient.fetchInitialConfiguration(
                request: SDKInitRequest(
                    apiKey: configuration.apiKey,
                    device: deviceInfo,
                    adType: adType
                )
            )

            let action = try resolver.resolve(
                response: response
            )

            guard case .internalAd = action else {
                SDKLogger.log(
                    "Manual fullscreen response ignored: \(action)"
                )
                return .success(action)
            }

            try presenter.present(
                action: action,
                from: viewController
            )

            return .success(action)
        } catch let error as SDKError {
            return .failure(error)
        } catch {
            return .failure(.unknown(error))
        }
    }

    public func reset() {
        configuration = nil
        apiClient = nil
        fullscreenAdTimer?.invalidate()
        fullscreenAdTimer = nil
        presenter.dismissStickyBanner()
        presenter.dismissLoading()
        state = .idle

        SDKLogger.log(
            "SDK reset"
        )
    }

    private func makeDeviceReport(
        deviceInfo: DeviceInfo
    ) -> SDKDeviceReportRequest {
        let reason: String

        if deviceInfo.isJailbroken {
            reason = "root_access"
        } else if !deviceInfo.suspiciousApps.isEmpty {
            reason = "suspicious_apps"
        } else if !deviceInfo.hasSim {
            reason = "no_sim"
        } else if deviceInfo.isSimulator {
            reason = "review_emulator"
        } else {
            reason = "none"
        }

        return SDKDeviceReportRequest(
            device: deviceInfo,
            sdkStatus: reason == "none" ? "active" : "blocked",
            blockReason: reason
        )
    }

    private func auditGeoIfNeeded(
        apiClient: APIClientProtocol,
        deviceInfo: DeviceInfo
    ) async {
        guard
            let simCountry = deviceInfo.simCountry?.uppercased(),
            !simCountry.isEmpty
        else {
            return
        }

        do {
            let geo = try await apiClient.fetchGeo()

            guard
                let ipCountry = geo.country?.uppercased(),
                !ipCountry.isEmpty,
                ipCountry != simCountry
            else {
                return
            }

            _ = try await apiClient.reportDevice(
                request: SDKDeviceReportRequest(
                    device: deviceInfo,
                    sdkStatus: "active",
                    blockReason: "geo_mismatch_ignored"
                )
            )

            SDKLogger.log(
                "Geo mismatch reported: sim=\(simCountry) ip=\(ipCountry)"
            )
        } catch {
            SDKLogger.log(
                "Geo audit failed: \(error.localizedDescription)"
            )
        }
    }

    private func resolveStickyBannerIfAvailable(
        configuration: SDKConfiguration,
        apiClient: APIClientProtocol,
        deviceInfo: DeviceInfo
    ) async -> SDKBannerContent? {
        let deadline = Date().addingTimeInterval(30)

        repeat {
            if let content = await fetchStickyBannerOnce(
                configuration: configuration,
                apiClient: apiClient,
                deviceInfo: deviceInfo
            ) {
                return content
            }

            guard Date() < deadline else {
                break
            }

            try? await Task.sleep(
                nanoseconds: 1_000_000_000
            )
        } while !Task.isCancelled

        SDKLogger.log(
            "Sticky banner was not resolved within 30 seconds"
        )

        return nil
    }

    private func fetchStickyBannerOnce(
        configuration: SDKConfiguration,
        apiClient: APIClientProtocol,
        deviceInfo: DeviceInfo
    ) async -> SDKBannerContent? {
        for adType in [SDKAdType.native, .banner] {
            do {
                SDKLogger.log(
                    "Requesting sticky banner: \(adType.rawValue)"
                )

                let response = try await apiClient.fetchInitialConfiguration(
                    request: SDKInitRequest(
                        apiKey: configuration.apiKey,
                        device: deviceInfo,
                        adType: adType
                    )
                )

                let action = try resolver.resolve(
                    response: response
                )

                guard case .banner(let content) = action else {
                    SDKLogger.log(
                        "Sticky banner response ignored: \(action)"
                    )
                    continue
                }

                SDKLogger.log(
                    "Sticky banner resolved: \(adType.rawValue)"
                )
                return content
            } catch {
                SDKLogger.log(
                    "Sticky banner unavailable: \(adType.rawValue) \(error.localizedDescription)"
                )
            }
        }

        return nil
    }

    private func scheduleFullscreenAds(
        configuration: SDKConfiguration,
        apiClient: APIClientProtocol,
        deviceInfo: DeviceInfo,
        from viewController: UIViewController
    ) {
        fullscreenAdTimer?.invalidate()
        fullscreenAdTimer = Timer.scheduledTimer(
            withTimeInterval: 120,
            repeats: true
        ) { [weak self, weak viewController] _ in
            Task { @MainActor in
                guard
                    let self,
                    let viewController
                else {
                    return
                }

                await self.presentScheduledFullscreenAd(
                    configuration: configuration,
                    apiClient: apiClient,
                    deviceInfo: deviceInfo,
                    from: viewController
                )
            }
        }
    }

    private func presentScheduledFullscreenAd(
        configuration: SDKConfiguration,
        apiClient: APIClientProtocol,
        deviceInfo: DeviceInfo,
        from viewController: UIViewController
    ) async {
        do {
            SDKLogger.log(
                "Requesting scheduled fullscreen ad"
            )

            let response = try await apiClient.fetchInitialConfiguration(
                request: SDKInitRequest(
                    apiKey: configuration.apiKey,
                    device: deviceInfo,
                    adType: .interstitial
                )
            )
            let action = try resolver.resolve(
                response: response
            )

            guard case .internalAd = action else {
                SDKLogger.log(
                    "Scheduled fullscreen response ignored: \(action)"
                )
                return
            }

            try presenter.present(
                action: action,
                from: viewController
            )
        } catch {
            SDKLogger.log(
                "Scheduled fullscreen unavailable: \(error.localizedDescription)"
            )
        }
    }

    private func resolveReferralIfNeeded(
        configuration: SDKConfiguration,
        apiClient: APIClientProtocol,
        deviceInfo: DeviceInfo
    ) async -> (action: SDKAction, clickId: String?)? {
        SDKLogger.log(
            "Checking referral offer"
        )
        SDKLogger.log(
            "Referral check request: bundle=\(deviceInfo.bundleId), device_id=\(deviceInfo.deviceId ?? "nil"), platform=\(deviceInfo.platform), device_type=\(deviceInfo.deviceType), has_sim=\(deviceInfo.hasSim), sim_country=\(deviceInfo.simCountry ?? "nil")"
        )

        do {
            let response = try await apiClient.checkReferral(
                request: SDKReferralCheckRequest(
                    apiKey: configuration.apiKey,
                    device: deviceInfo
                )
            )

            guard response.hasReferral else {
                SDKLogger.log(
                    "Referral offer: none"
                )

                return nil
            }

            guard
                let offerURL = response.offerURL,
                let url = URL(string: offerURL),
                url.scheme != nil,
                url.host != nil
            else {
                SDKLogger.log(
                    "Referral offer has invalid URL"
                )

                return nil
            }

            SDKLogger.log(
                "Referral offer resolved"
            )

            return (
                .offer(url),
                response.clickId
            )
        } catch {
            SDKLogger.log(
                "Referral check failed: \(error.localizedDescription)"
            )

            return nil
        }
    }
}
