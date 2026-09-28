# 홈구장 (Homefield)

집에서 TV로 KBO 경기를 볼 때, 야구장에 있는 것처럼 만들어 주는 iOS 앱입니다.

- **타자가 나오면** 그 선수의 **등장곡** → **응원가**를 재생합니다.
- **경기 상황이 나오면** 나레이션을 합니다: 플라이아웃, 도루 성공, 홈런(투런/쓰리런/만루 자동 구분), 득점, 실책, 삼진, 안타, 볼넷, 병살, 폭투, 투수 교체 등.
- 문자중계가 TV보다 빠른 만큼 **방송 싱크(지연)** 를 맞출 수 있습니다.

## 구조

```
Packages/HomefieldCore/     플랫폼 독립 로직 (Swift Package, 단위 테스트 포함)
  RelayTextClassifier       "구자욱 : 좌익수 플라이 아웃" → .flyOut 같은 문자중계 해석
  GameEventDetector         중계 스냅샷에서 새로 생긴 상황만 뽑기 (처음엔 현재 타자만)
  NarrationComposer         이벤트 묶음 → 오디오 큐 (홈런+홈인 합치기 등)
  LiveGameMonitor           주기적으로 중계를 가져와 이벤트 스트림으로
  NaverSportsProvider       네이버 스포츠 KBO 문자중계 데이터
  DemoGameProvider          실제 경기 없이 시험하는 가상 경기
Homefield/                  iOS 앱 (SwiftUI, iOS 17+)
  Audio/                    AudioDirector(흐름), MusicDeck(Apple Music·파일 재생), Narrator(한국어 TTS)
  Songs/SongLibrary         선수별 등장곡/응원가, 팀 응원가 지정 (기기에 저장)
  Live/LiveGameSession      경기 한 개를 따라가며 방송 지연만큼 늦춰서 재생
  Views/                    경기 목록, 라이브 화면, 응원가 관리, 설정
```

## 빌드

저장소에 `Homefield.xcodeproj`가 들어 있어서 바로 열면 됩니다.

```sh
open Homefield.xcodeproj
```

프로젝트 파일은 `project.yml`을 원본으로 [XcodeGen](https://github.com/yonaskolb/XcodeGen)이 만듭니다.

- `Homefield/` 폴더 안에 Swift 파일을 추가·삭제하는 것은 Xcode에서 해도 괜찮습니다.
- 빌드 설정, Info.plist 항목, 타깃 같은 **프로젝트 설정은 `project.yml`에서 바꾸세요.** Xcode 화면에서 바꾸면 다음에 다시 생성할 때 덮어써집니다.
- `project.yml`을 바꾼 PR을 올리면 CI(**Xcode project sync**)가 프로젝트를 다시 만들어 PR 브랜치에 자동으로 커밋합니다. 직접 만들려면:

```sh
brew install xcodegen
xcodegen generate
```

- Signing & Capabilities에서 팀을 지정하세요.
- Apple Music 재생을 쓰려면 Apple Developer 사이트의 App ID 설정에서 **MusicKit** 서비스를 켜야 하고, 기기에 Apple Music 구독이 있어야 합니다. 구독이 없으면 **파일에서 가져오기**로 가진 음악 파일(mp3, m4a 등)을 지정하면 됩니다.

코어 로직 테스트:

```sh
cd Packages/HomefieldCore && swift test
```

## TestFlight 배포

`v1.0.0` 같은 태그를 푸시하거나 GitHub Actions 탭에서 **TestFlight** 워크플로를 직접 실행하면, 빌드해서 TestFlight에 올립니다. 빌드 번호는 워크플로 실행 번호로 자동으로 매겨집니다.

처음 한 번만 준비하면 됩니다:

1. [Apple Developer Program](https://developer.apple.com/programs/) 가입 (연 $99).
2. Certificates, Identifiers & Profiles → Identifiers에서 번들 ID `com.bravekoon.homefield` 등록. App Services에서 **MusicKit** 체크.
3. [App Store Connect](https://appstoreconnect.apple.com) → 앱 → **+** 로 같은 번들 ID의 앱 등록.
4. App Store Connect → 사용자 및 액세스 → 통합 → **App Store Connect API** 에서 키 생성. 역할은 **Admin**이어야 합니다 (CI가 배포 인증서와 프로비저닝 프로파일을 자동으로 만들 수 있어야 해서). `.p8` 파일은 한 번만 내려받을 수 있습니다.
5. GitHub 저장소 → Settings → Secrets and variables → Actions 에 다음을 등록:

| Secret | 값 |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | API 키의 Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | 같은 화면 위쪽의 Issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | `.p8` 파일 내용 전체 (`-----BEGIN PRIVATE KEY-----` 포함) |
| `APPLE_TEAM_ID` | Membership 페이지의 Team ID (10자리) |

업로드가 끝나고 App Store Connect에서 처리가 완료되면 (보통 10~30분) TestFlight 탭에서 **내부 테스터**에게 바로 배포할 수 있습니다. 외부 테스터는 Beta App Review 심사를 거칩니다.

앱 아이콘(`Homefield/Assets.xcassets/AppIcon.appiconset/AppIcon.png`)은 임시 아이콘입니다. 1024×1024, 투명 배경 없는 PNG로 바꿔 넣으면 됩니다.

## 사용법

1. **설정 → 데모 경기 사용**을 켜고 경기 탭에서 데모 경기를 열어 동작을 확인합니다.
2. **응원가 탭**에서 팀/선수별로 등장곡과 응원가를 지정합니다. 경기를 한 번 열면 라인업 선수가 자동으로 추가됩니다. 라이브 화면의 **노래 지정** 버튼으로 지금 타석에 선 선수에게 바로 지정할 수도 있습니다.
3. 선수 응원가가 없으면 **팀 응원가**가 나옵니다.
4. TV보다 소리가 먼저 나오면 **방송 싱크**를 늘려서 맞추세요.
5. 설정의 **상황별 나레이션**에서 상황마다 켜고 끄거나 문구를 바꿀 수 있습니다 (예: 실책 → "에러!").

## 주의

- **데이터 출처**: 네이버 스포츠의 공개되지 않은 내부 API(`api-gw.sports.naver.com`)를 사용합니다. 응답 형식이 예고 없이 바뀔 수 있고, 이용약관상 개인 용도를 넘어서는 사용(앱스토어 배포 등)은 문제가 될 수 있습니다. 배포하려면 정식 데이터 제공 계약이 필요합니다. 형식이 바뀌면 `NaverSportsProvider.swift`의 `NaverMapping`만 고치면 되도록 분리해 두었고, 다른 데이터 소스는 `GameDataProvider` 프로토콜을 구현해 붙이면 됩니다.
- **저작권**: 등장곡·응원가 음원은 앱에 포함되어 있지 않습니다. 사용자가 Apple Music이나 직접 가진 파일로 지정합니다.
- **백그라운드**: iOS는 소리가 나지 않는 앱을 백그라운드에서 멈춥니다. 경기 중에는 앱을 화면에 켜 두세요 (라이브 화면에서는 화면 자동 잠금을 끕니다).
