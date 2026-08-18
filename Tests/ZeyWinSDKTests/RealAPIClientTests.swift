import XCTest
@testable import ZeyWinSDK

final class RealAPIClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchInitialConfigurationPostsJSONAndDecodesResponse() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/ads/request")!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(
                request.url,
                expectedURL
            )
            XCTAssertEqual(
                request.httpMethod,
                "POST"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-ZeyWin-API-Key"),
                "test-key"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Custom"),
                "custom-value"
            )

            let body = try XCTUnwrap(request.httpBodyStream?.readAllData())
            let decoded = try JSONDecoder().decode(
                SDKInitRequest.self,
                from: body
            )

            XCTAssertEqual(
                decoded.apiKey,
                "test-key"
            )
            XCTAssertEqual(
                decoded.device.bundleId,
                "com.example.app"
            )
            XCTAssertEqual(
                decoded.adType,
                .interstitial
            )
            XCTAssertTrue(
                decoded.device.hasSim
            )
            XCTAssertEqual(
                decoded.device.simCountry,
                "US"
            )
            XCTAssertTrue(
                decoded.device.isSimulator
            )
            XCTAssertTrue(
                decoded.device.isSandboxReceipt
            )
            XCTAssertEqual(
                decoded.device.suspiciousApps,
                [
                    "cydia"
                ]
            )

            let data = Data(
                """
                {
                  "success": true,
                  "data": {
                    "ad_id": "ad-1",
                    "ad_type": "interstitial",
                    "media_type": "html",
                    "media_url": "https://example.com/ad.html",
                    "click_url": "https://example.com/click"
                  }
                }
                """.utf8
            )
            let response = HTTPURLResponse(
                url: expectedURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            return (
                response,
                data
            )
        }

        let client = RealAPIClient(
            configuration: SDKProductionConfiguration(
                baseURL: URL(string: "https://api.example.com/v1")!,
                initEndpoint: "/ads/request",
                additionalHeaders: [
                    "X-Custom": "custom-value"
                ]
            ),
            urlSession: makeURLSession()
        )

        let response = try await client.fetchInitialConfiguration(
            request: makeRequest()
        )

        XCTAssertEqual(
            response.action,
            "interstitial"
        )
        XCTAssertEqual(
            response.mediaURL,
            "https://example.com/ad.html"
        )
        XCTAssertEqual(
            response.clickURL,
            "https://example.com/click"
        )
    }

    func testFetchInitialConfigurationThrowsServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            return (
                response,
                Data(
                    """
                    {
                      "success": false,
                      "error": "app inactive"
                    }
                    """.utf8
                )
            )
        }

        let client = RealAPIClient(
            configuration: SDKProductionConfiguration(
                baseURL: URL(string: "https://api.example.com")!
            ),
            urlSession: makeURLSession()
        )

        do {
            _ = try await client.fetchInitialConfiguration(
                request: makeRequest()
            )
            XCTFail("Expected request to throw")
        } catch SDKError.server(let message) {
            XCTAssertEqual(
                message,
                "app inactive"
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchInitialConfigurationThrowsHTTPStatus() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!

            return (
                response,
                Data()
            )
        }

        let client = RealAPIClient(
            configuration: SDKProductionConfiguration(
                baseURL: URL(string: "https://api.example.com")!
            ),
            urlSession: makeURLSession()
        )

        do {
            _ = try await client.fetchInitialConfiguration(
                request: makeRequest()
            )
            XCTFail("Expected request to throw")
        } catch SDKError.httpStatus(let statusCode) {
            XCTAssertEqual(
                statusCode,
                503
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchInitialConfigurationThrowsDecodingFailed() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            return (
                response,
                Data("{".utf8)
            )
        }

        let client = RealAPIClient(
            configuration: SDKProductionConfiguration(
                baseURL: URL(string: "https://api.example.com")!
            ),
            urlSession: makeURLSession()
        )

        do {
            _ = try await client.fetchInitialConfiguration(
                request: makeRequest()
            )
            XCTFail("Expected request to throw")
        } catch SDKError.decodingFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchInitialConfigurationThrowsInvalidURLForRelativeBaseURL() async {
        let client = RealAPIClient(
            configuration: SDKProductionConfiguration(
                baseURL: URL(string: "/relative")!
            ),
            urlSession: makeURLSession()
        )

        do {
            _ = try await client.fetchInitialConfiguration(
                request: makeRequest()
            )
            XCTFail("Expected request to throw")
        } catch SDKError.invalidURL {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReportDevicePostsUnityCompatiblePayload() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/device/report")!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(
                request.url,
                expectedURL
            )
            XCTAssertEqual(
                request.httpMethod,
                "POST"
            )

            let body = try XCTUnwrap(request.httpBodyStream?.readAllData())
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )

            XCTAssertEqual(
                json["bundle_id"] as? String,
                "com.example.app"
            )
            XCTAssertEqual(
                json["has_sim"] as? Bool,
                true
            )
            XCTAssertEqual(
                json["sim_country"] as? String,
                "US"
            )
            XCTAssertEqual(
                json["sdk_status"] as? String,
                "active"
            )
            XCTAssertEqual(
                json["block_reason"] as? String,
                "none"
            )
            XCTAssertEqual(
                json["detected_packages"] as? String,
                "cydia,simulator"
            )

            let response = HTTPURLResponse(
                url: expectedURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            return (
                response,
                Data(
                    """
                    {
                      "success": true,
                      "data": {
                        "sdk_status": "blocked",
                        "block_reason": "review_emulator"
                      }
                    }
                    """.utf8
                )
            )
        }

        let client = RealAPIClient(
            configuration: SDKProductionConfiguration(
                baseURL: URL(string: "https://api.example.com/v1")!
            ),
            urlSession: makeURLSession()
        )

        let response = try await client.reportDevice(
            request: SDKDeviceReportRequest(
                device: makeRequest().device,
                sdkStatus: "active",
                blockReason: "none"
            )
        )

        XCTAssertEqual(
            response.sdkStatus,
            "blocked"
        )
        XCTAssertEqual(
            response.blockReason,
            "review_emulator"
        )
    }

    func testTrackEventAcceptsSuccessWithoutData() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/events")!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(
                request.url,
                expectedURL
            )
            XCTAssertEqual(
                request.httpMethod,
                "POST"
            )

            let body = try XCTUnwrap(request.httpBodyStream?.readAllData())
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )

            XCTAssertEqual(
                json["api_key"] as? String,
                "test-key"
            )
            XCTAssertEqual(
                json["bundle_id"] as? String,
                "com.example.app"
            )
            XCTAssertEqual(
                json["ad_id"] as? String,
                "ad-1"
            )
            XCTAssertEqual(
                json["event_type"] as? String,
                "impression"
            )

            let response = HTTPURLResponse(
                url: expectedURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            return (
                response,
                Data(
                    """
                    {
                      "success": true
                    }
                    """.utf8
                )
            )
        }

        let client = RealAPIClient(
            configuration: SDKProductionConfiguration(
                baseURL: URL(string: "https://api.example.com/v1")!
            ),
            urlSession: makeURLSession()
        )

        await client.trackEvent(
            request: SDKEventRequest(
                apiKey: "test-key",
                device: makeRequest().device,
                adId: "ad-1",
                adType: "banner",
                eventType: "impression"
            )
        )
    }

    private func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [
            MockURLProtocol.self
        ]
        return URLSession(
            configuration: configuration
        )
    }

    private func makeRequest() -> SDKInitRequest {
        SDKInitRequest(
            apiKey: "test-key",
            device: DeviceInfo(
                bundleId: "com.example.app",
                appVersion: "1.0",
                deviceModel: "iPhone",
                osName: "iOS",
                osVersion: "17.0",
                locale: "en_US",
                timezone: "UTC",
                hasSim: true,
                simCountry: "US",
                isSimulator: true,
                isSandboxReceipt: true,
                suspiciousApps: [
                    "cydia"
                ]
            )
        )
    }
}

private final class MockURLProtocol: URLProtocol {

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(
        with request: URLRequest
    ) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(
                self,
                didLoad: data
            )
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(
                self,
                didFailWithError: error
            )
        }
    }

    override func stopLoading() {}
}

private extension InputStream {

    func readAllData() -> Data {
        open()
        defer {
            close()
        }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: bufferSize
        )
        defer {
            buffer.deallocate()
        }

        while hasBytesAvailable {
            let count = read(
                buffer,
                maxLength: bufferSize
            )

            if count > 0 {
                data.append(
                    buffer,
                    count: count
                )
            } else {
                break
            }
        }

        return data
    }
}
