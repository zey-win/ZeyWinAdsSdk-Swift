public enum SDKState: Equatable, Sendable {
    case idle
    case initializing
    case ready
    case collectingDeviceInfo
    case requesting
    case presenting
    case failed(String)
}
