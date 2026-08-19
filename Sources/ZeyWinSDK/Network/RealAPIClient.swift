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
            apiKey: nil,
            defaultResponse: SDKDeviceReportResponse(
                sdkStatus: "active"
            )
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

    func checkReferral(
        request: SDKReferralCheckRequest
    ) async throws -> SDKReferralResponse {

        logReferralRequest(
            request
        )

        let response: SDKReferralResponse = try await postAPIResponse(
            path: "/referral/check",
            body: request,
            apiKey: request.apiKey
        )

        SDKLogger.log(
            "Referral check response: has_referral=\(response.hasReferral), click_id=\(response.clickId ?? "nil"), offer_url_present=\(response.offerURL?.isEmpty == false)"
        )

        return response
    }

    private func logReferralRequest(
        _ request: SDKReferralCheckRequest
    ) {
        guard SDKLogger.isEnabled else {
            return
        }

        do {
            let data = try jsonEncoder.encode(
                request
            )
            var object = try JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any]

            if let apiKey = object?["api_key"] as? String {
                object?["api_key"] = maskedAPIKey(
                    apiKey
                )
            }

            let sanitizedData = try JSONSerialization.data(
                withJSONObject: object ?? [:],
                options: [.sortedKeys]
            )
            let body = String(
                data: sanitizedData,
                encoding: .utf8
            ) ?? "{}"

            SDKLogger.log(
                "Referral check body: \(body)"
            )
        } catch {
            SDKLogger.log(
                "Referral check body log failed: \(error.localizedDescription)"
            )
        }
    }

    private func maskedAPIKey(
        _ apiKey: String
    ) -> String {
        guard apiKey.count > 10 else {
            return "***"
        }

        return "\(apiKey.prefix(5))...\(apiKey.suffix(4))"
    }

    func checkReferralByClick(
        request: SDKReferralCheckByClickRequest
    ) async throws -> SDKReferralResponse {

        try await postAPIResponse(
            path: "/referral/check-by-click",
            body: request,
            apiKey: request.apiKey
        )
    }

    func markReferralDelivered(
        request: SDKReferralDeliveredRequest
    ) async {
        do {
            let _: SDKEmptyResponse = try await postAPIResponse(
                path: "/referral/delivered",
                body: request,
                apiKey: request.apiKey,
                defaultResponse: SDKEmptyResponse()
            )

            SDKLogger.log(
                "Referral delivered: \(request.clickId ?? "unknown")"
            )
        } catch {
            SDKLogger.log(
                "Referral delivery failed: \(error.localizedDescription)"
            )
        }
    }

    func fetchGeo() async throws -> SDKGeoResponse {
        try await getAPIResponse(
            path: "/geo"
        )
    }

    func trackEvent(
        request: SDKEventRequest
    ) async {
        do {
            let _: SDKEmptyResponse = try await postAPIResponse(
                path: "/events",
                body: request,
                apiKey: request.apiKey,
                defaultResponse: SDKEmptyResponse()
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

    func trackWebView(
        request: SDKWebViewEventRequest
    ) async {
        do {
            let _: SDKEmptyResponse = try await postAPIResponse(
                path: "/events/webview",
                body: request,
                apiKey: request.apiKey,
                defaultResponse: SDKEmptyResponse()
            )

            SDKLogger.log(
                "WebView render tracked: \(request.status)"
            )
        } catch {
            SDKLogger.log(
                "WebView render tracking failed: \(request.status) \(error.localizedDescription)"
            )
        }
    }

    private func postAPIResponse<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        apiKey: String?,
        defaultResponse: Response? = nil
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
            urlRequest.setValue(
                apiKey,
                forHTTPHeaderField: "X-API-Key"
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
            if let apiResponse = try? jsonDecoder.decode(
                SDKAPIResponse<Response>.self,
                from: data
            ) {
                guard apiResponse.success else {
                    throw SDKError.server(
                        apiResponse.error ?? "Unknown error"
                    )
                }

                if let sdkResponse = apiResponse.data {
                    return sdkResponse
                }

                if let defaultResponse {
                    return defaultResponse
                }

                throw SDKError.invalidResponse
            }

            if let sdkResponse = try? jsonDecoder.decode(
                Response.self,
                from: data
            ) {
                return sdkResponse
            }

            guard
                (try? JSONSerialization.jsonObject(with: data)) != nil
            else {
                throw SDKError.decodingFailed(
                    DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: [],
                            debugDescription: "Invalid JSON response"
                        )
                    )
                )
            }

            if let defaultResponse {
                return defaultResponse
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

    private func getAPIResponse<Response: Decodable>(
        path: String
    ) async throws -> Response {
        let url = try makeURL(
            path: path
        )
        var urlRequest = URLRequest(
            url: url
        )
        urlRequest.httpMethod = "GET"
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        configuration.additionalHeaders.forEach { key, value in
            urlRequest.setValue(
                value,
                forHTTPHeaderField: key
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
            return try jsonDecoder.decode(
                Response.self,
                from: data
            )
        } catch {
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
