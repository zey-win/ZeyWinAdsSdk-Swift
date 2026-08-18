import Foundation

final class SDKTrackingClient {

    static let shared = SDKTrackingClient()

    private let urlSession: URLSession
    private let lock = NSLock()

    private var apiClient: APIClientProtocol?
    private var apiKey: String?
    private var device: DeviceInfo?

    init(
        urlSession: URLSession = .shared
    ) {
        self.urlSession = urlSession
    }

    func configure(
        apiClient: APIClientProtocol?,
        apiKey: String,
        device: DeviceInfo
    ) {
        lock.lock()
        self.apiClient = apiClient
        self.apiKey = apiKey
        self.device = device
        lock.unlock()
    }

    func fire(
        _ tracking: SDKAdTracking?,
        event: String
    ) {
        sendEvent(
            tracking,
            event: event
        )

        let url = tracking?.url(
            for: event
        )

        guard let url else {
            return
        }

        Task.detached(priority: .utility) { [urlSession] in
            var request = URLRequest(
                url: url
            )
            request.httpMethod = "GET"
            request.timeoutInterval = 10

            do {
                _ = try await urlSession.data(
                    for: request
                )

                SDKLogger.log(
                    "Tracking \(event) sent: \(url.absoluteString)"
                )
            } catch {
                SDKLogger.log(
                    "Tracking \(event) failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func sendEvent(
        _ tracking: SDKAdTracking?,
        event: String
    ) {
        guard
            let tracking,
            let adId = tracking.adId,
            !adId.isEmpty
        else {
            return
        }

        lock.lock()
        let apiClient = self.apiClient
        let apiKey = self.apiKey
        let device = self.device
        lock.unlock()

        guard
            let apiClient,
            let apiKey,
            let device
        else {
            return
        }

        let request = SDKEventRequest(
            apiKey: apiKey,
            device: device,
            adId: adId,
            adType: tracking.adType,
            eventType: event
        )

        Task.detached(priority: .utility) {
            await apiClient.trackEvent(
                request: request
            )
        }
    }
}

private extension SDKAdTracking {

    func url(
        for event: String
    ) -> URL? {
        switch event {
        case "impression":
            return impressionURL

        case "click":
            return clickURL

        case "complete":
            return completeURL

        case "reward":
            return rewardURL

        default:
            return nil
        }
    }
}
