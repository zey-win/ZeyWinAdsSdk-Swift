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

    func fetchInitialConfiguration(
        request: SDKInitRequest
    ) async throws -> SDKInitResponse {

        let url = try makeInitURL()
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        urlRequest.setValue(
            request.apiKey,
            forHTTPHeaderField: "X-ZeyWin-API-Key"
        )

        configuration.additionalHeaders.forEach { key, value in
            urlRequest.setValue(
                value,
                forHTTPHeaderField: key
            )
        }

        do {
            urlRequest.httpBody = try jsonEncoder.encode(
                request
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
                SDKAPIResponse<SDKInitResponse>.self,
                from: data
            )

            guard apiResponse.success else {
                throw SDKError.server(
                    apiResponse.error ?? "Unknown error"
                )
            }

            guard let sdkResponse = apiResponse.data else {
                throw SDKError.invalidResponse
            }

            return sdkResponse
        } catch {
            if let sdkError = error as? SDKError {
                throw sdkError
            }

            throw SDKError.decodingFailed(
                error
            )
        }
    }

    private func makeInitURL() throws -> URL {
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
        let endpointPath = configuration.initEndpoint
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
