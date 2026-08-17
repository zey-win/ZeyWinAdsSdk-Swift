import XCTest
@testable import ZeyWinSDK

final class RealAPIClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchInitialConfigurationPostsJSONAndDecodesResponse() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/sdk/init")!

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

            let data = try JSONEncoder().encode(
                SDKInitResponse(
                    action: "offer",
                    url: "https://example.com"
                )
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
                initEndpoint: "/sdk/init",
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
            "offer"
        )
        XCTAssertEqual(
            response.url,
            "https://example.com"
        )
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
                timezone: "UTC"
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
