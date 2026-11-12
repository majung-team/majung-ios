<div align="center">
  <img src="docs/media/majung-icon.png" width="76" alt="마중 앱 아이콘" />
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
| 화면 설계 | [01 화면 설계와 이용 흐름](https://app.notion.com/p/4146da9ae26a8064b544d805ddc1b578) | 탭 구조 및 주요 화면 이용 흐름 |
| 데이터 모델 | [02 데이터 모델과 ERD](https://app.notion.com/p/4146da9ae26a809b928cffed612504f4) | 테이블·화면 기능 매핑 |
| 체크리스트 | [03 개발 로드맵과 체크리스트](https://app.notion.com/p/4146da9ae26a80d6bb0fe7bab3c929e2) | 단계별 구현·검증 현황 |
| Figma | [Majung iOS 디자인](https://www.figma.com/design/XfEx8dmI2KqQuFZQAtpm0I/Majung?node-id=170-3) | UI 시안 및 인터랙티브 프로토타입 |
| 개발 규칙 | [CONTRIBUTING.md](CONTRIBUTING.md) | 브랜치·커밋 규칙 및 실행 기준 |

---

## 주요 기능

- **초대 링크 게스트 참여**: 로그인 없이 전달받은 초대 링크로 만날 장소를 먼저 확인한 뒤 바로 참여하거나 대기 중에 나갈 수 있습니다.
- **카카오 로그인 · 계정 관리**: 인앱 브라우저(`ASWebAuthenticationSession`) 기반 카카오 로그인과 닉네임·마중 ID 설정, 지인 검색·연결, 회원 탈퇴를 지원합니다.
- **차량 QR 연결**: 카메라 QR 스캔 또는 링크 입력으로 운전자 차량과 손쉽게 연결·해제할 수 있습니다.
- **장소 · 주소 검색**: 서버의 카카오 로컬 검색으로 상호명과 도로명·지번 주소를 찾아주며, 서버 검색을 쓸 수 없는 환경에서는 Apple 지도(`MKLocalSearch`) 검색으로 자동 전환합니다.
- **실시간 위치 · 소통**: 실시간 연결(SSE)로 차량 위치와 도착 예정 시간을 받아보고, 탑승 준비 상태·빠른 메시지 전달 및 만날 장소 변경을 제안합니다.
- **알림 및 화면 테마**: 라이트·다크 모드를 지원하며, 도착 임박·도착 로컬 알림과 APNs 원격 푸시 연동을 제공합니다.

---

## 구조

```text
Majung/
├── App/           # 앱 진입점, 푸시 등록(AppDelegate), 루트 화면 전환(ContentView)
├── Core/          # API 클라이언트(Account, Pickup, RideRequest, VehicleLink) 및 SSE 파서
├── DesignSystem/  # 브랜드 컬러(#2669DD)·심볼 및 공통 카드·검색·지도 컴포넌트
└── Features/      # Onboarding, Account, VehicleLinks, RideRequest, Pickup 화면·뷰모델
MajungTests/       # 모델·검증기·SSE·트래커 단위 테스트
MajungUITests/     # 내장 테스트 서버 기반 UI E2E 테스트
```

---

## 검증 범위 및 남은 확인 사항

- 단위 테스트(`MajungTests`)와 UI 테스트(`MajungUITests`)로 주요 사용자 흐름을 검증하며, 실행 결과는 [iOS CI](https://github.com/majung-team/majung-ios/actions/workflows/ios.yml)에서 확인할 수 있습니다.
- iPhone 실기기에서의 카카오 로그인, 카메라 QR 스캔, 실주행 실시간 위치·장소 검색 연동은 실기기 연결 후 검증할 예정입니다.
- 백그라운드 원격 푸시(APNs)와 유니버설 링크(Associated Domains)는 유료 Apple Developer 계정 프로비저닝 및 서버 APNs 키 설정 적용 시 활성화됩니다.

---

## 관련 저장소

- [majung](https://github.com/majung-team/majung) · 전체 서비스 소개 및 아키텍처
- [majung-backend](https://github.com/majung-team/majung-backend) · Spring Boot API 및 운영 서버
- [majung-web](https://github.com/majung-team/majung-web) · 모바일 웹 및 AASA 설정
- [majung-vehicle-app](https://github.com/majung-team/majung-vehicle-app) · Android Automotive OS 차량 앱
