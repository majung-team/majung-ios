<div align="center">
  <img src="Majung/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="76" alt="마중 앱 아이콘" />
  <h1>마중 iOS</h1>
  <p>가족이나 친구가 차로 데리러 올 때, 만날 장소와 실시간 차량 위치·도착 예정 시간·탑승 준비 상태를 함께 확인하는 iOS 앱입니다.</p>
  <p>
    <a href="https://app.notion.com/p/4146da9ae26a81f8b525ece0ed1c1962">Notion 워크스페이스</a> ·
    <a href="https://www.figma.com/design/XfEx8dmI2KqQuFZQAtpm0I/Majung?node-id=170-3">Figma 디자인</a> ·
    <a href="https://github.com/majung-team/majung">마중 전체 프로젝트</a>
  </p>
</div>

---

## 설계 및 참고 문서

| 구분 | 링크 | 설명 |
| --- | --- | --- |
| Notion 홈 | [마중 iOS (3차 앱 프로젝트)](https://app.notion.com/p/4146da9ae26a81f8b525ece0ed1c1962) | 프로젝트 개요 및 진행 관리 |
| 화면 설계 | [01 화면 설계와 이용 흐름](https://app.notion.com/p/4146da9ae26a8064b544d805ddc1b578) | 탭 구조 및 핵심 10개 화면 흐름 |
| 데이터 모델 | [02 데이터 모델과 ERD](https://app.notion.com/p/4146da9ae26a809b928cffed612504f4) | 테이블·화면 기능 매핑 |
| 체크리스트 | [03 개발 로드맵과 체크리스트](https://app.notion.com/p/4146da9ae26a80d6bb0fe7bab3c929e2) | 단계별 구현·검증 현황 |
| Figma | [Majung iOS 디자인](https://www.figma.com/design/XfEx8dmI2KqQuFZQAtpm0I/Majung?node-id=170-3) | UI 시안 및 인터랙티브 프로토타입 |
| 개발 규칙 | [CONTRIBUTING.md](CONTRIBUTING.md) | 브랜치·커밋 규칙 및 실행 기준 |

---

## 주요 기능

- **초대 링크 게스트 참여**: 로그인 없이 `#join` 초대 링크로 만날 장소를 먼저 확인하고 참여·대기 이탈(`POST /api/v1/pickups/{id}/leave`) 가능
- **카카오 로그인 · 계정 관리**: `ASWebAuthenticationSession` 기반 PKCE 로그인, 닉네임·마중 ID 관리, 지인 검색·연결, 회원 탈퇴(`DELETE /api/v1/accounts/me`)
- **차량 QR 연결**: `DataScannerViewController` 카메라 스캔 및 링크 입력을 통한 차량 페어링 승인·해제
- **한국 장소·주소 검색**: 백엔드 카카오 로컬 검색 프록시(`/api/v1/places/search`)로 장소명·분류·도로명/지번 주소를 조회하고, 미지원 시 `MKLocalSearch`로 폴백
- **실시간 픽업 · 소통**: SSE(`pickups/{id}/events`, `ride-requests/events`) 기반 차량 위치·ETA 갱신, 준비 상태 전달, 퀵 메시지 전송, 장소 변경 제안
- **알림 및 테마**: 라이트·다크 모드 및 앱 실행 중 도착 전·도착 로컬 알림 지원 (`AppDelegate` APNs 디바이스 토큰 등록 훅 포함)

---

## 구조

```text
Majung/
├── App/           # 앱 진입점, AppDelegate, 루트 상태 전환(ContentView)
├── Core/          # API 클라이언트(Account, Pickup, RideRequest, VehicleLink) 및 SSE 파서
├── DesignSystem/  # 브랜드 컬러(#2669DD)·마크 및 공통 카드·검색·지도 컴포넌트
└── Features/      # Onboarding, Account, VehicleLinks, RideRequest, Pickup 화면·뷰모델
MajungTests/       # 모델·검증기·SSE·트래커 단위 테스트
MajungUITests/     # LocalE2EServer 기반 UI E2E 테스트
```

---

## 실행 및 테스트

- **요구 환경**: Xcode 16+, iOS 17.0+, SwiftUI / Swift Observation (`@Observable`)
- **연동 서버**: 기본 `https://majung.cloud/api/v1` (UI E2E 실행 시 `MAJUNG_TEST_PORT`로 로컬 목 서버 연결)

```sh
# 시뮬레이터 빌드 확인
xcodebuild -project Majung.xcodeproj -scheme Majung \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# 단위 테스트 + UI E2E 테스트 실행 (<SIMULATOR_UDID> 지정)
xcodebuild -project Majung.xcodeproj -scheme Majung \
  -destination "platform=iOS Simulator,id=<SIMULATOR_UDID>" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:MajungTests -only-testing:MajungUITests test
```

---

## 검증 범위 및 남은 확인 사항

- `MajungTests`(24개) 및 `LocalE2EServer` 기반 `MajungUITests`(6개)로 검증합니다. 차량 연결은 자동 갱신과 수동 상태 확인을 별도로 검사합니다. 최근 실행 결과는 [iOS CI](https://github.com/majung-team/majung-ios/actions/workflows/ios.yml)에서 확인할 수 있습니다.
- 실기기(`iPhone`)에서의 카카오 OAuth·차량 QR 스캔·실주행 SSE/카카오 장소 검색 종단간 확인은 기기 연결 후 진행할 예정입니다.
- Universal Links(`Associated Domains`) 및 백그라운드 APNs 푸시 발송(`aps-environment`)은 유료 Apple Developer 계정 프로비저닝과 서버 APNs 키 설정 적용 시 활성화됩니다.

---

## 관련 저장소

- [majung](https://github.com/majung-team/majung) · 전체 서비스 소개 및 아키텍처
- [majung-backend](https://github.com/majung-team/majung-backend) · Spring Boot API 및 운영 서버
- [majung-web](https://github.com/majung-team/majung-web) · 모바일 웹 및 AASA 설정
- [majung-vehicle-app](https://github.com/majung-team/majung-vehicle-app) · Android Automotive OS 차량 앱
