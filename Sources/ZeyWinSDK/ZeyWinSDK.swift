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

            do {
                let reportResponse = try await apiClient.reportDevice(
                    request: localReport
                )

                SDKLogger.log(
                    "Device report verdict: \(reportResponse.sdkStatus) \(reportResponse.blockReason ?? "none")"
                )

                if reportResponse.sdkStatus == "blocked" {
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
                    state = .ready

                    return .success(
                        .blocked(reason: localReport.blockReason)
                    )
                }
            }

            let request = SDKInitRequest(
                apiKey: configuration.apiKey,
                device: deviceInfo
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

                state = .ready

                return .success(
                    action
                )

            case .blocked(let reason):
                SDKLogger.log(
                    "Backend verdict: blocked(\(reason ?? "unknown"))"
                )

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

    public func reset() {
        configuration = nil
        apiClient = nil
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
}
