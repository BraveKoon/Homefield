#!/usr/bin/env python3
"""네이버 스포츠 KBO API 응답을 확인한다 (앱의 NaverSportsProvider 가 가정한 경로·필드 점검용).

최근 경기 하나를 골라 후보 경로들을 호출하고, 상태 코드와 응답 구조(키 목록, 첫 항목 예시)를 출력한다.
"""
import datetime as dt
import json
import sys
import urllib.error
import urllib.request

BASE = "https://api-gw.sports.naver.com"
HEADERS = {
    "Referer": "https://m.sports.naver.com/",
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
    "Accept": "application/json",
}
KST = dt.timezone(dt.timedelta(hours=9))


def get(path):
    request = urllib.request.Request(BASE + path, headers=HEADERS)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        return error.code, None
    except Exception as error:  # noqa: BLE001
        return f"ERR {error}", None


def shape(value, depth=0, max_depth=3):
    """키 구조만 요약"""
    if depth >= max_depth:
        return type(value).__name__
    if isinstance(value, dict):
        return {key: shape(item, depth + 1, max_depth) for key, item in value.items()}
    if isinstance(value, list):
        return [shape(value[0], depth + 1, max_depth), f"... ({len(value)})"] if value else []
    return type(value).__name__


def show(title, value, limit=4000):
    text = json.dumps(value, ensure_ascii=False, indent=1)
    print(f"--- {title} ---")
    print(text[:limit] + ("\n... (생략)" if len(text) > limit else ""))


def find_game():
    today = dt.datetime.now(KST).date()
    for back in range(0, 10):
        day = (today - dt.timedelta(days=back)).isoformat()
        status, body = get(
            f"/schedule/games?fields=basic&upperCategoryId=kbaseball&categoryId=kbo&fromDate={day}&toDate={day}&size=100"
        )
        games = ((body or {}).get("result") or {}).get("games") or []
        print(f"schedule {day}: HTTP {status}, {len(games)} games, statuses={[g.get('statusCode') for g in games]}")
        if back == 0 and games:
            show("schedule game[0]", games[0], 2500)
        # 진행 중인 경기 우선, 없으면 끝난 경기
        for wanted in ("STARTED", "RESULT"):
            for game in games:
                if game.get("statusCode") == wanted and not game.get("cancel"):
                    return game
    return None


def main():
    game = find_game()
    if not game:
        print("최근 10일 안에 경기를 찾지 못했습니다")
        return 1
    game_id = game["gameId"]
    print(f"\n선택한 경기: {game_id} {game.get('awayTeamName')} vs {game.get('homeTeamName')} ({game.get('statusCode')})\n")

    status, body = get(f"/schedule/games/{game_id}")
    print(f"/schedule/games/{game_id}: HTTP {status}")
    if body:
        show("game summary shape", shape(body, max_depth=3))

    candidates = [
        f"/game/{game_id}/relay",
        f"/game/{game_id}/relay?inning=1",
        f"/schedule/games/{game_id}/relay",
        f"/schedule/games/{game_id}/relay?inning=1",
        f"/schedule/games/{game_id}/relay?inning=3",
    ]
    working = None
    for path in candidates:
        status, body = get(path)
        keys = list(((body or {}).get("result") or {}).keys()) if isinstance(body, dict) else None
        print(f"{path}: HTTP {status}, result keys={keys}")
        if status == 200 and body and working is None:
            working = (path, body)

    if not working:
        print("\n동작하는 relay 경로를 찾지 못했습니다")
        return 1

    path, body = working
    print(f"\n=== 동작하는 경로: {path} ===")
    result = body.get("result") or {}
    show("result shape", shape(result, max_depth=4), 6000)
    relay = result.get("textRelayData") or {}
    relays = relay.get("textRelays") or []
    if relays:
        first = dict(relays[0])
        options = first.pop("textOptions", [])
        show("textRelays[0] (textOptions 제외)", first, 2000)
        for index, option in enumerate(options[:4]):
            show(f"textRelays[0].textOptions[{index}]", option, 3000)
    for side in ("homeLineup", "awayLineup"):
        lineup = relay.get(side) or {}
        print(f"{side} keys: {list(lineup.keys())}")
        for key, value in lineup.items():
            if isinstance(value, list) and value:
                show(f"{side}.{key}[0]", value[0], 1500)
    for key in relay:
        if key not in ("textRelays", "homeLineup", "awayLineup"):
            show(f"textRelayData.{key}", relay[key], 1500)
    return 0


if __name__ == "__main__":
    sys.exit(main())
