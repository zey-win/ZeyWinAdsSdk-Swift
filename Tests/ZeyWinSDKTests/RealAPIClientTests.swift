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
                request.value(forHTTPHeaderField: "X-API-Key"),
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

    func testFetchGeoUsesGetAndDecodesCountry() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/geo")!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(
                request.url,
                expectedURL
            )
            XCTAssertEqual(
                request.httpMethod,
                "GET"
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
                      "country": "us"
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

        let response = try await client.fetchGeo()

        XCTAssertEqual(
            response.country,
            "US"
        )
    }

    func testCheckReferralPostsPayloadAndDecodesOffer() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/referral/check")!

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
                request.value(forHTTPHeaderField: "X-API-Key"),
                "test-key"
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
                json["device_id"] as? String,
                "device-1"
            )
            XCTAssertEqual(
                json["sim_country"] as? String,
                "US"
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
                        "has_referral": true,
                        "offer_url": "https://example.com/force",
                        "click_id": "force_123"
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

        let response = try await client.checkReferral(
            request: SDKReferralCheckRequest(
                apiKey: "test-key",
                device: makeRequest().device
            )
        )

        XCTAssertTrue(
            response.hasReferral
        )
        XCTAssertEqual(
            response.offerURL,
            "https://example.com/force"
        )
        XCTAssertEqual(
            response.clickId,
            "force_123"
        )
    }

    func testCheckReferralByClickPostsClickId() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/referral/check-by-click")!

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
                json["click_id"] as? String,
                "click-1"
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
                        "has_referral": false
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

        let response = try await client.checkReferralByClick(
            request: SDKReferralCheckByClickRequest(
                apiKey: "test-key",
                device: makeRequest().device,
                clickId: "click-1"
            )
        )

        XCTAssertFalse(
            response.hasReferral
        )
    }

    func testMarkReferralDeliveredAcceptsSuccessWithoutData() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/referral/delivered")!

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
                json["click_id"] as? String,
                "force_123"
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

        await client.markReferralDelivered(
            request: SDKReferralDeliveredRequest(
                apiKey: "test-key",
                device: makeRequest().device,
                clickId: "force_123"
            )
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

    func testTrackWebViewPostsShownEvent() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/events/webview")!

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
                json["ad_type"] as? String,
                "interstitial"
            )
            XCTAssertEqual(
                json["status"] as? String,
                "shown"
            )
            XCTAssertNil(
                json["fail_reason"]
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

        await client.trackWebView(
            request: SDKWebViewEventRequest(
                apiKey: "test-key",
                device: makeRequest().device,
                adId: "ad-1",
                adType: "interstitial",
                status: "shown"
            )
        )
    }

    func testReportDeviceAcceptsSuccessWithoutData() async throws {
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

        let response = try await client.reportDevice(
            request: SDKDeviceReportRequest(
                device: makeRequest().device,
                sdkStatus: "active",
                blockReason: "none"
            )
        )

        XCTAssertEqual(
            response.sdkStatus,
            "active"
        )
        XCTAssertNil(
            response.blockReason
        )
    }

    func testAdsRequestDecodesCompleteInterstitialContract() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/ads/request")!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, expectedURL)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-ZeyWin-API-Key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "test-key")

            let body = try XCTUnwrap(request.httpBodyStream?.readAllData())
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["api_key"] as? String, "test-key")
            XCTAssertEqual(json["bundle_id"] as? String, "com.example.app")
            XCTAssertEqual(json["ad_type"] as? String, "interstitial")
            XCTAssertEqual(json["country"] as? String, "US")
            XCTAssertEqual(json["language"] as? String, "en")
            XCTAssertEqual(json["sdk_version"] as? String, SDKInitRequest.sdkVersion)

            return (
                HTTPURLResponse(url: expectedURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(
                    """
                    {
                      "success": true,
                      "data": {
                        "ad_id": "ad-interstitial",
                        "ad_type": "interstitial",
                        "media_type": "video/mp4",
                        "media_url": "https://cdn.example.com/ad.mp4",
                        "click_url": "https://example.com/click",
                        "store_url": "https://apps.apple.com/app/id123",
                        "impression_url": "https://track.example.com/impression",
                        "click_tracking_url": "https://track.example.com/click",
                        "complete_url": "https://track.example.com/complete",
                        "reward_url": "https://track.example.com/reward",
                        "duration_sec": 30,
                        "skip_after_sec": 5
                      }
                    }
                    """.utf8
                )
            )
        }

        let response = try await makeClient().fetchInitialConfiguration(request: makeRequest())

        XCTAssertEqual(response.action, "interstitial")
        XCTAssertEqual(response.adId, "ad-interstitial")
        XCTAssertEqual(response.adType, .interstitial)
        XCTAssertEqual(response.mediaType, "video/mp4")
        XCTAssertEqual(response.mediaURL, "https://cdn.example.com/ad.mp4")
        XCTAssertEqual(response.clickURL, "https://example.com/click")
        XCTAssertEqual(response.storeURL, "https://apps.apple.com/app/id123")
        XCTAssertEqual(response.impressionURL, "https://track.example.com/impression")
        XCTAssertEqual(response.clickTrackingURL, "https://track.example.com/click")
        XCTAssertEqual(response.completeURL, "https://track.example.com/complete")
        XCTAssertEqual(response.rewardURL, "https://track.example.com/reward")
        XCTAssertEqual(response.durationSec, 30)
        XCTAssertEqual(response.skipAfterSec, 5)
    }

    func testAdsRequestDecodesBannerAndNativeContracts() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/ads/request")!

        for adType in [SDKAdType.banner, .native] {
            MockURLProtocol.requestHandler = { request in
                XCTAssertEqual(request.url, expectedURL)
                XCTAssertEqual(request.httpMethod, "POST")

                let body = try XCTUnwrap(request.httpBodyStream?.readAllData())
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["ad_type"] as? String, adType.rawValue)

                return (
                    HTTPURLResponse(url: expectedURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "success": true,
                          "data": {
                            "ad_type": "\(adType.rawValue)",
                            "media_type": "image/png",
                            "media_url": "https://cdn.example.com/\(adType.rawValue).png",
                            "icon_url": "https://cdn.example.com/icon.png",
                            "click_url": "https://example.com/\(adType.rawValue)",
                            "ad_text": "Contract title",
                            "ad_body": "Contract body",
                            "cta_text": "Install",
                            "cta_text_2": "Details",
                            "popup_delay_sec": 10,
                            "popup_repeat_sec": 60
                          }
                        }
                        """.utf8
                    )
                )
            }

            let response = try await makeClient().fetchInitialConfiguration(
                request: makeRequest(adType: adType)
            )

            XCTAssertEqual(response.action, adType.rawValue)
            XCTAssertEqual(response.adType, adType)
            XCTAssertEqual(response.mediaType, "image/png")
            XCTAssertEqual(response.mediaURL, "https://cdn.example.com/\(adType.rawValue).png")
            XCTAssertEqual(response.iconURL, "https://cdn.example.com/icon.png")
            XCTAssertEqual(response.clickURL, "https://example.com/\(adType.rawValue)")
            XCTAssertEqual(response.adText, "Contract title")
            XCTAssertEqual(response.adBody, "Contract body")
            XCTAssertEqual(response.ctaText, "Install")
            XCTAssertEqual(response.ctaText2, "Details")
            XCTAssertEqual(response.popupDelaySec, 10)
            XCTAssertEqual(response.popupRepeatSec, 60)
        }
    }

    func testDeviceReportEncodesCompletePayloadAndDecodesBlockedState() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/device/report")!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, expectedURL)
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try XCTUnwrap(request.httpBodyStream?.readAllData())
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["device_id"] as? String, "device-1")
            XCTAssertEqual(json["bundle_id"] as? String, "com.example.app")
            XCTAssertEqual(json["has_sim"] as? Bool, true)
            XCTAssertEqual(json["sim_country"] as? String, "US")
            XCTAssertEqual(json["detected_packages"] as? String, "cydia,simulator")
            XCTAssertEqual(json["device_clean"] as? Bool, false)
            XCTAssertEqual(json["sdk_status"] as? String, "blocked")
            XCTAssertEqual(json["block_reason"] as? String, "review_emulator")
            XCTAssertEqual(json["device_model"] as? String, "iPhone")
            XCTAssertEqual(json["os_version"] as? String, "iOS 17.0")
            XCTAssertNotNil(json["battery_level"] as? Int)
            XCTAssertNotNil(json["is_charging"] as? Bool)

            return (
                HTTPURLResponse(url: expectedURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{ \"success\": true, \"data\": { \"sdk_status\": \"blocked\", \"block_reason\": \"review_emulator\" } }".utf8)
            )
        }

        let response = try await makeClient().reportDevice(
            request: SDKDeviceReportRequest(
                device: makeRequest().device,
                sdkStatus: "blocked",
                blockReason: "review_emulator"
            )
        )

        XCTAssertEqual(response.sdkStatus, "blocked")
        XCTAssertEqual(response.blockReason, "review_emulator")
    }

    func testFetchGeoDecodesCountryCodeAlias() async throws {
        let expectedURL = URL(string: "https://api.example.com/v1/geo")!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, expectedURL)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            return (
                HTTPURLResponse(url: expectedURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{ \"country_code\": \"kz\" }".utf8)
            )
        }

        let response = try await makeClient().fetchGeo()
        XCTAssertEqual(response.country, "KZ")
    }

    func testReferralContractsCoverFalseMissingInvalidAndCheckByClick() async throws {
        let checkURL = URL(string: "https://api.example.com/v1/referral/check")!
        let clickURL = URL(string: "https://api.example.com/v1/referral/check-by-click")!
        let checkRequest = SDKReferralCheckRequest(apiKey: "test-key", device: makeRequest().device)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, checkURL)
            let body = try XCTUnwrap(request.httpBodyStream?.readAllData())
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["api_key"] as? String, "test-key")
            XCTAssertEqual(json["bundle_id"] as? String, "com.example.app")
            XCTAssertEqual(json["device_id"] as? String, "device-1")
            XCTAssertEqual(json["sim_country"] as? String, "US")
            return (
                HTTPURLResponse(url: checkURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{ \"success\": true, \"data\": { \"has_referral\": false } }".utf8)
            )
        }

        let noReferral = try await makeClient().checkReferral(request: checkRequest)
        XCTAssertFalse(noReferral.hasReferral)
        XCTAssertNil(noReferral.offerURL)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, checkURL)
            return (
                HTTPURLResponse(url: checkURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{ \"success\": true, \"data\": { \"has_referral\": true, \"offer_url\": \"not a URL\" } }".utf8)
            )
        }

        let invalidURL = try await makeClient().checkReferral(request: checkRequest)
        XCTAssertTrue(invalidURL.hasReferral)
        XCTAssertEqual(invalidURL.offerURL, "not a URL")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, clickURL)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-ZeyWin-API-Key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "test-key")
            let body = try XCTUnwrap(request.httpBodyStream?.readAllData())
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["api_key"] as? String, "test-key")
            XCTAssertEqual(json["bundle_id"] as? String, "com.example.app")
            XCTAssertEqual(json["device_id"] as? String, "device-1")
            XCTAssertEqual(json["click_id"] as? String, "click-1")
            return (
                HTTPURLResponse(url: clickURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{ \"success\": true, \"data\": { \"has_referral\": true, \"offer_url\": \"https://example.com/offer\", \"click_id\": \"click-1\" } }".utf8)
            )
        }

        let byClick = try await makeClient().checkReferralByClick(
            request: SDKReferralCheckByClickRequest(
                apiKey: "test-key",
                device: makeRequest().device,
                clickId: "click-1"
            )
        )
        XCTAssertTrue(byClick.hasReferral)
        XCTAssertEqual(byClick.offerURL, "https://example.com/offer")
        XCTAssertEqual(byClick.clickId, "click-1")
    }

    func testReferralDeliveredAndEventContractsIncludeTrackingData() async throws {
        let deliveredURL = URL(string: "https://api.example.com/v1/referral/delivered")!
        let eventURL = URL(string: "https://api.example.com/v1/events")!
        let webViewURL = URL(string: "https://api.example.com/v1/events/webview")!
        var paths: [String] = []

        MockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            paths.append(url.path)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-ZeyWin-API-Key"), "test-key")
            let body = try XCTUnwrap(request.httpBodyStream?.readAllData())
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

            if url == deliveredURL {
                XCTAssertEqual(json["bundle_id"] as? String, "com.example.app")
                XCTAssertEqual(json["device_id"] as? String, "device-1")
                XCTAssertEqual(json["click_id"] as? String, "force-1")
            } else if url == eventURL {
                XCTAssertEqual(json["app_id"] as? String, "com.example.app")
                XCTAssertEqual(json["ad_id"] as? String, "ad-1")
                XCTAssertEqual(json["ad_type"] as? String, "rewarded")
                XCTAssertEqual(json["event_type"] as? String, "reward")
                XCTAssertEqual(json["device_model"] as? String, "iPhone")
                XCTAssertEqual(json["os_version"] as? String, "iOS 17.0")
                XCTAssertEqual(json["sdk_version"] as? String, SDKInitRequest.sdkVersion)
            } else if url == webViewURL {
                XCTAssertEqual(json["ad_id"] as? String, "ad-1")
                XCTAssertEqual(json["ad_type"] as? String, "interstitial")
                XCTAssertEqual(json["status"] as? String, "failed")
                XCTAssertEqual(json["fail_reason"] as? String, "video_playback_error")
            } else {
                XCTFail("Unexpected endpoint: \(url)")
            }

            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{ \"success\": true }".utf8)
            )
        }

        let client = makeClient()
        let device = makeRequest().device
        await client.markReferralDelivered(
            request: SDKReferralDeliveredRequest(apiKey: "test-key", device: device, clickId: "force-1")
        )
        await client.trackEvent(
            request: SDKEventRequest(apiKey: "test-key", device: device, adId: "ad-1", adType: "rewarded", eventType: "reward")
        )
        await client.trackWebView(
            request: SDKWebViewEventRequest(
                apiKey: "test-key",
                device: device,
                adId: "ad-1",
                adType: "interstitial",
                status: "failed",
                failReason: "video_playback_error"
            )
        )

        XCTAssertEqual(paths, [deliveredURL.path, eventURL.path, webViewURL.path])
    }

    func testAdsRequestRejectsMalformedEnvelopeData() async {
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{ \"success\": true, \"data\": { \"duration_sec\": \"invalid\" } }".utf8)
            )
        }

        do {
            _ = try await makeClient().fetchInitialConfiguration(request: makeRequest())
            XCTFail("Expected request to throw")
        } catch SDKError.decodingFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAdsRequestRejectsEmptyResponse() async {
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        do {
            _ = try await makeClient().fetchInitialConfiguration(request: makeRequest())
            XCTFail("Expected request to throw")
        } catch SDKError.decodingFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeviceReportThrowsHTTP4xx() async {
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 403,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        do {
            _ = try await makeClient().reportDevice(
                request: SDKDeviceReportRequest(
                    device: makeRequest().device,
                    sdkStatus: "active",
                    blockReason: "none"
                )
            )
            XCTFail("Expected request to throw")
        } catch SDKError.httpStatus(let statusCode) {
            XCTAssertEqual(statusCode, 403)
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

    private func makeClient() -> RealAPIClient {
        RealAPIClient(
            configuration: SDKProductionConfiguration(
                baseURL: URL(string: "https://api.example.com/v1")!
            ),
            urlSession: makeURLSession()
        )
    }

    private func makeRequest(
        adType: SDKAdType = .interstitial
    ) -> SDKInitRequest {
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
                language: "en",
                country: "US",
                platform: "ios",
                deviceType: "phone",
                deviceId: "device-1",
                hasSim: true,
                simCountry: "US",
                isSimulator: true,
                isSandboxReceipt: true,
                suspiciousApps: [
                    "cydia"
                ]
            ),
            adType: adType
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
