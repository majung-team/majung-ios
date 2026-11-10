# 마중 iOS

초대를 받거나 마중을 요청하고, 만날 장소와 차량 도착 예정 시간을 확인하는 탑승자용 iOS 앱입니다. 현재는 SwiftUI 시작 화면과 개발 환경을 갖춘 상태입니다.

## 실행

iOS 17 이상을 대상으로 합니다. Xcode 16 이상에서 `Majung.xcodeproj`를 열고 `Majung` 스킴과 iPhone 시뮬레이터를 선택한 뒤 실행합니다. 시뮬레이터 빌드에는 서명이 필요 없습니다.

```sh
xcodebuild -project Majung.xcodeproj -scheme Majung -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

- `Majung/MajungApp.swift` — 앱 진입점
- `Majung/ContentView.swift` — 시작 화면
- `.github/workflows/ios.yml` — 시뮬레이터 빌드와 PR 검사

화면 흐름과 개발 순서는 [마중 iOS 기획 문서](https://app.notion.com/p/iOS-3-4146da9ae26a81f8b525ece0ed1c1962)에서 볼 수 있습니다. [마중 전체 프로젝트](https://github.com/majung-team/majung)에는 차량 앱과 탑승자 웹 사용법이 있습니다.

작업을 시작하기 전에 [기여 가이드](CONTRIBUTING.md)를 확인해 주세요.
