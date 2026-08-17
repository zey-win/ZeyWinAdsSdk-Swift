# ZeyWinSDK

Нативный iOS SDK на Swift для получения remote action, показа offer/internal ad в `WKWebView` и отображения banner-сценария.

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

По умолчанию production-клиент отправляет `POST /sdk/init` на `https://api.zeywin.com`.
Если backend URL или endpoint отличаются, передайте `SDKProductionConfiguration`:

```swift
ZeyWinSDK.shared.initialize(
    apiKey: "live-key",
    mode: .production,
    productionConfiguration: SDKProductionConfiguration(
        baseURL: URL(string: "https://api.example.com/v1")!,
        initEndpoint: "/sdk/init",
        timeout: 20,
        additionalHeaders: [
            "X-App-Channel": "ios"
        ]
    )
)
```

Production request отправляется как JSON body `SDKInitRequest` и дополнительно передает API key в header `X-ZeyWin-API-Key`.

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

`SDKInitResponse.action` поддерживает:

- `offer` с `url`
- `internal_ad` с `url`
- `banner` с `url` и опциональным `title`
- `blocked` с опциональным `reason`
- `none`

Неподдерживаемое action значение возвращается как `SDKError.unsupportedAction`.
