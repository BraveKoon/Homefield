# 계정·기기 동기화 설정 (Apple 로그인 + Supabase)

앱에서 Apple로 로그인하면 카드·포인트·응원 라인업·응원팀과 설정·직관 기록·선수별 응원가 지정이
같은 계정의 다른 기기와 이어진다. 로그인은 선택이라서 로그인하지 않아도 지금처럼 기기 안에서만 쓸 수 있다.
음원 파일은 저작권 때문에 동기화하지 않는다 (곡 정보만 이어지고, 파일은 기기마다 다시 가져온다).

## 구조

```
앱 ── Apple로 로그인 ──▶ identity token ──▶ Supabase Auth ──▶ 앱 전용 세션
앱 ── 저장·불러오기 ──▶ Supabase (user_state 표, 본인 줄만 접근)
```

- 서버는 Supabase 하나다. 별도 서버 코드는 없다.
- 계정은 Apple 이 주는 사용자 ID 로 구분한다. 이메일(비공개 릴레이일 수 있다)은 쓰거나 저장하지 않는다.
- 앱에 들어가는 값은 프로젝트 주소와 anon 키뿐이다. anon 키는 공개해도 되는 값이고, 데이터는 행 단위 보안(RLS)으로 보호한다.
  **service_role 키는 앱에도 저장소에도 넣지 않는다.**
- 저장은 계정당 한 줄(JSON)이다. 저장할 때 `revision` 을 1 올리고, 올리는 순간 서버의 revision 이 내가 마지막으로 본 값과 같을 때만 성공한다.
  다른 기기가 먼저 저장했다면 실패하고, 앱이 서버 것을 받아 와서 다시 시도한다.
- 같은 계정을 처음 연결하는 기기에 이미 쌓은 데이터가 있고 서버에도 데이터가 있으면, 앱이 어느 쪽을 쓸지 묻는다.

## 설정 순서 (저장소 주인이 한 번 하면 된다)

### 1. Apple Developer 에서 Sign in with Apple 켜기

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) → `com.bravekoon.homefield` 선택
2. Capabilities 에서 **Sign in with Apple** 체크 → Save
3. 위젯 확장(`com.bravekoon.homefield.HomefieldWidgets`)은 건드리지 않는다

이 단계가 끝나기 전에 앱에 해당 entitlement 를 넣으면 TestFlight 내보내기가 "Authentication failed" 로 실패한다
(App Group 때와 같다). 그래서 앱 쪽 entitlement 는 이 단계를 끝냈다고 알려 준 다음에 넣는다.

### 2. Supabase 프로젝트 만들기

1. [supabase.com](https://supabase.com) 에서 새 프로젝트를 만든다 (무료 플랜으로 충분하다. 지역은 Northeast Asia (Seoul) 를 권장).
2. **SQL Editor** 에 `supabase/schema.sql` 전체를 붙여 넣고 실행한다.
3. **Authentication → Sign In / Providers → Apple** 을 켜고 **Client IDs** 칸에 `com.bravekoon.homefield` 를 넣는다.
   앱 안에서 바로 로그인하는 방식에서는 Secret Key 칸을 비워 둬도 된다.
4. **Project Settings → API** 에서 아래 두 값을 알려 준다 (둘 다 공개해도 되는 값이다).
   - Project URL (`https://xxxx.supabase.co`)
   - anon (public) key

### 3. 앱 심사를 내기 전에 해야 하는 것

- **개인정보 처리방침 수정**: 지금 방침은 "개인정보를 수집하지 않고 로그인 기능이 없다"고 되어 있다.
  로그인을 넣으면 Apple 로그인으로 받는 식별자·이메일(선택)과 동기화 데이터를 쓴다고 바꿔야 한다. 앱 릴리스 전에 같이 올린다.
- **App Store Connect 의 '앱 개인정보' 항목**: '데이터 수집 안 함' 에서 바꿔야 한다 (이메일 주소, 사용자 ID, 게임플레이 콘텐츠 등).
- **계정 삭제**: 앱 안에서 계정을 지울 수 있어야 한다 (`delete_my_account()` 로 서버 데이터와 계정을 지운다).
- **Apple 토큰 해지**: Sign in with Apple 계정을 지울 때는 Apple 쪽 토큰도 해지(revoke)해야 한다.
  이건 Apple 개발자 키(.p8)가 필요해서 Supabase Edge Function 으로 따로 만든다. TestFlight 에는 필요 없고 심사 제출 전에 한다.

## 알려진 한계

- 포인트와 카드는 기기에서 계산해서 올리는 값이라 서버가 조작을 막아 주지 않는다 (지금도 쿠폰 코드가 앱 안에 들어 있다).
  친구끼리 쓰는 TestFlight 단계에서는 감수하고, 랭킹이나 거래를 만들게 되면 서버에서 검증하도록 바꾼다.
- 두 기기를 동시에 쓰면 나중에 저장한 쪽이 이긴다. 한 기기의 최근 변경이 사라질 수 있다.
