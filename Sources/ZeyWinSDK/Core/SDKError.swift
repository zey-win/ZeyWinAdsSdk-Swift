import Foundation

public enum SDKError: LocalizedError {

    case notInitialized
    case apiClientUnavailable
    case alreadyRunning
    case invalidURL
    case invalidResponse
    case encodingFailed(Error)
    case decodingFailed(Error)
    case httpStatus(Int)
    case network(Error)
    case unsupportedAction(String)
    case presentationFailed
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "SDK is not initialized."

        case .apiClientUnavailable:
            return "API client is unavailable."

        case .alreadyRunning:
            return "SDK request is already running."

        case .invalidURL:
            return "Invalid URL."

        case .invalidResponse:
            return "Invalid server response."

        case .encodingFailed(let error):
            return "Failed to encode request: \(error.localizedDescription)"

        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"

        case .httpStatus(let statusCode):
            return "Unexpected server status code: \(statusCode)."

        case .network(let error):
            return "Network error: \(error.localizedDescription)"

        case .unsupportedAction(let value):
            return "Unsupported SDK action: \(value)"

        case .presentationFailed:
            return "Failed to present SDK content."

        case .unknown(let error):
            return "Unknown SDK error: \(error.localizedDescription)"
        }
    }
}
