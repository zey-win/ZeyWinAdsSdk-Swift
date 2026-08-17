# ZeyWinSDK

Нативный iOS SDK на Swift для запроса ZeyWin Ads backend, показа fullscreen offer в `WKWebView` и отображения banner-сценария.

## Возможности

- Swift Package
- Public API: `initialize()` + `start(from:)`
- SDK state machine
- DeviceInfoProvider
- APIClientProtocol
- MockAPIClient
- RealAPIClient с POST JSON production-интеграцией
- DTO request/response
- ContentResolver
- WKWebView presentation
- Banner presentation
- Logger
- Unit tests для resolver и production API client

## Быстрый старт

Подключите package локально к тестовому iOS-приложению и используйте:

```swift
import UIKit
import ZeyWinSDK

final class ViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        ZeyWinSDK.shared.initialize(
            apiKey: "test-key",
            mode: .mock(.offer)
        )

        Task {
            let result = await ZeyWinSDK.shared.start(from: self)

            switch result {
            case .success(let action):
                print("SDK action:", action)

            case .failure(let error):
                print("SDK error:", error.localizedDescription)
            }
        }
    }
}
```

## Production mode

По умолчанию production-клиент отправляет `POST /ads/request` на `https://zeywin-ads-api.whiteapps.workers.dev/api/v1`.
Если backend URL или endpoint отличаются, передайте `SDKProductionConfiguration`:

```swift
ZeyWinSDK.shared.initialize(
    apiKey: "live-key",
    mode: .production,
    productionConfiguration: SDKProductionConfiguration(
        baseURL: URL(string: "https://zeywin-ads-api.whiteapps.workers.dev/api/v1")!,
        initEndpoint: "/ads/request",
        timeout: 20,
        additionalHeaders: [
            "X-App-Channel": "ios"
        ]
    )
)
```

Production request совместим с Unity SDK `AdRequest` contract и отправляется flat snake_case JSON:

- `bundle_id`
- `api_key`
- `ad_type`
- `country`
- `language`
- `platform`
- `device_type`
- `device_model`
- `os_version`
- `sdk_version`
- `device_id`
- `app_version`
- `has_sim`
- `sim_country`

API key также передается в header `X-ZeyWin-API-Key`.

## Mock сценарии

```swift
.mock(.offer)
.mock(.internalAd)
.mock(.banner)
.mock(.blocked)
.mock(.nothing)
.mock(.networkError)
```

## Response contract

Production response ожидается в формате:

```json
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
```

Поддерживаемые `ad_type`:

- `interstitial`
- `rewarded`
- `banner`
- `native`
- `popup`

Для совместимости с ранним mock contract `SDKInitResponse.action` также поддерживает `offer`, `internal_ad`, `banner`, `blocked`, `none`.

`success=false` возвращается как `SDKError.server`.
