import Foundation

final class RealAPIClient: APIClientProtocol {

    private let configuration: SDKProductionConfiguration
    private let urlSession: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(
        configuration: SDKProductionConfiguration = .default,
        urlSession: URLSession? = nil,
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder

        if let urlSession {
            self.urlSession = urlSession
        } else {
            let sessionConfiguration = URLSessionConfiguration.default
            sessionConfiguration.timeoutIntervalForRequest = configuration.timeout
            sessionConfiguration.timeoutIntervalForResource = configuration.timeout
            self.urlSession = URLSession(
                configuration: sessionConfiguration
            )
        }
    }

    func reportDevice(
        request: SDKDeviceReportRequest
    ) async throws -> SDKDeviceReportResponse {

        try await postAPIResponse(
            path: "/device/report",
            body: request,
            apiKey: nil
        )
    }

    func fetchInitialConfiguration(
        request: SDKInitRequest
    ) async throws -> SDKInitResponse {

        try await postAPIResponse(
            path: configuration.initEndpoint,
            body: request,
            apiKey: request.apiKey
        )
    }

    func trackEvent(
        request: SDKEventRequest
    ) async {
        do {
            let _: SDKEmptyResponse = try await postAPIResponse(
                path: "/events",
                body: request,
                apiKey: request.apiKey
            )

            SDKLogger.log(
                "Event tracked: \(request.eventType)"
            )
        } catch {
            SDKLogger.log(
                "Event tracking failed: \(request.eventType) \(error.localizedDescription)"
            )
        }
    }

    private func postAPIResponse<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        apiKey: String?
    ) async throws -> Response {

        let url = try makeURL(
            path: path
        )
        var urlRequest = URLRequest(
            url: url
        )
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        if let apiKey {
            urlRequest.setValue(
                apiKey,
                forHTTPHeaderField: "X-ZeyWin-API-Key"
            )
        }

        configuration.additionalHeaders.forEach { key, value in
            urlRequest.setValue(
                value,
                forHTTPHeaderField: key
            )
        }

        do {
            urlRequest.httpBody = try jsonEncoder.encode(
                body
            )
        } catch {
            throw SDKError.encodingFailed(
                error
            )
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await urlSession.data(
                for: urlRequest
            )
        } catch {
            throw SDKError.network(
                error
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SDKError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SDKError.httpStatus(
                httpResponse.statusCode
            )
        }

        do {
            let apiResponse = try jsonDecoder.decode(
                SDKAPIResponse<Response>.self,
                from: data
            )

            guard apiResponse.success else {
                throw SDKError.server(
                    apiResponse.error ?? "Unknown error"
                )
            }

            if let sdkResponse = apiResponse.data {
                return sdkResponse
            }

            if Response.self == SDKEmptyResponse.self {
                return SDKEmptyResponse() as! Response
            }

            throw SDKError.invalidResponse
        } catch {
            if let sdkError = error as? SDKError {
                throw sdkError
            }

            throw SDKError.decodingFailed(
                error
            )
        }
    }

    private func makeURL(
        path: String
    ) throws -> URL {
        guard
            var components = URLComponents(
                url: configuration.baseURL,
                resolvingAgainstBaseURL: false
            ),
            components.scheme != nil,
            components.host != nil
        else {
            throw SDKError.invalidURL
        }

        let basePath = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let path = [
            basePath,
            endpointPath
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "/")

        components.path = path.isEmpty ? "" : "/\(path)"

        guard let url = components.url else {
            throw SDKError.invalidURL
        }

        return url
    }
}

private struct SDKEmptyResponse: Decodable {
    init() {}
}
