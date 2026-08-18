import Foundation

final class SDKTrackingRegistry {

    static let shared = SDKTrackingRegistry()

    private let lock = NSLock()
    private var storage: [String: SDKAdTracking] = [:]

    func register(
        tracking: SDKAdTracking,
        for url: URL
    ) {
        guard !tracking.isEmpty else {
            return
        }

        lock.lock()
        storage[url.absoluteString] = tracking
        lock.unlock()
    }

    func tracking(
        for url: URL
    ) -> SDKAdTracking? {
        lock.lock()
        let value = storage[url.absoluteString]
        lock.unlock()

        return value
    }
}
