# 홈구장 (Homefield) — 작업 규칙

## PR · 병합 · 배포 (저장소 주인이 정한 방식)

- PR은 **draft가 아닌 일반 PR**로 연다.
- CI(`HomefieldCore tests`, `iOS app build`, `Xcode project sync`)가 모두 통과하면 **확인을 묻지 말고 바로 병합**한다.
- 앱 코드가 바뀐 PR을 병합하면 **`main`에서 TestFlight 워크플로(`testflight.yml`)를 실행**하고 결과를 확인한다. 실패하면 로그를 보고 고친다.
- TestFlight 업로드가 성공하면 워크플로가 `build-<번호>` GitHub 프리릴리스를 자동으로 만든다.
- 버전 릴리스(예: v1.1)는 `project.yml` 맨 위 `settings`의 `MARKETING_VERSION`(앱·위젯 확장 공통)을 올려 병합한 뒤 `main`에서 TestFlight 워크플로를 `release_tag: v1.1` 입력으로 실행한다(태그 푸시는 세션 프록시가 막는다). 워크플로가 `v1.1` 태그와 정식 릴리스를 만든다.
- 문서만 바뀐 PR(README, docs/)은 병합만 하고 TestFlight는 돌리지 않아도 된다.
- App Store 심사 제출은 자동으로 하지 않는다. 네이버 비공식 API 사용 문제(`docs/app-store-metadata.md`의 심사 위험 요소)가 정리되기 전까지는 저장소 주인이 직접 결정한다.

## 코드

- 경기 데이터·계산 로직은 `Packages/HomefieldCore`(플랫폼 독립, 단위 테스트 필수), 화면·오디오는 `Homefield/`.
- 프로젝트 설정은 `project.yml`에서 바꾼다. `Homefield.xcodeproj`와 `Homefield/Info.plist`는 CI의 Xcode project sync가 다시 만들어 PR 브랜치에 커밋한다.
- 음원·선수 사진·구단 로고 파일은 저장소에 넣지 않는다 (저작권·초상권·상표권). 음원은 사용자가 기기에서 직접 가져온다.
- 구단 로고와 선수 사진은 저장소 주인 결정(비상업 개인 용도)으로 네이버 스포츠 이미지 주소에서 실행 중에 받아 기기 캐시에만 둔다. App Store 출시 전에는 다시 검토한다.
- 실존 선수의 기록·팀 이력 같은 내용을 지어내지 않는다. 확인된 데이터(네이버 스포츠, KBO 공식 기록)나 사용자가 입력한 내용만 쓴다. 나무위키는 robots.txt·약관상 자동 수집이 막혀 있어 쓰지 않는다.
