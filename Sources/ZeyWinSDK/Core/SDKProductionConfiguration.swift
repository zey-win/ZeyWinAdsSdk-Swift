import Foundation

public struct SDKProductionConfiguration: Equatable, Sendable {

    public static let `default` = SDKProductionConfiguration(
        baseURL: URL(string: "https://api.zeywin.com")!,
        initEndpoint: "/sdk/init"
    )

    public let baseURL: URL
    public let initEndpoint: String
    public let timeout: TimeInterval
    public let additionalHeaders: [String: String]

    public init(
        baseURL: URL,
        initEndpoint: String = "/sdk/init",
        timeout: TimeInterval = 30,
        additionalHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.initEndpoint = initEndpoint
        self.timeout = timeout
        self.additionalHeaders = additionalHeaders
    }
}
