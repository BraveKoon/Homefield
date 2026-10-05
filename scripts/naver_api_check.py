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

    batters = (relay.get("homeLineup") or {}).get("batter") or []
    pcode = str(batters[0].get("pcode")) if batters else None
    probe_players(game_id, pcode, game.get("homeTeamCode"))
    return 0


def probe_players(game_id, pcode, team_code):
    """이닝별 점수(R/H/E)·1군 엔트리(등록/말소)·시즌 기록 경로 확인 (로그가 잘리지 않게 짧게 출력)"""
    print("\n=== 이닝별 점수 / 엔트리 ===")
    status, body = get(f"/schedule/games/{game_id}")
    game = ((body or {}).get("result") or {}).get("game") or {}
    for key, value in game.items():
        lowered = key.lower()
        if any(word in lowered for word in ("inning", "rheb", "hit", "error", "ball", "score")):
            print(f"game.{key} = {json.dumps(value, ensure_ascii=False)[:300]}")

    status, body = get(f"/schedule/games/{game_id}/relay")
    relay = ((body or {}).get("result") or {}).get("textRelayData") or {}
    print(f"relay keys: {list(relay.keys())}")
    print(f"relay.inningScore = {json.dumps(relay.get('inningScore'), ensure_ascii=False)[:400]}")
    for side in ("homeLineup", "awayLineup"):
        batters = (relay.get(side) or {}).get("batter") or []
        print(f"{side}: batters={len(batters)} hits={sum(int(b.get('hit') or 0) for b in batters)}")
    for side in ("homeEntry", "awayEntry"):
        entry = relay.get(side) or {}
        print(f"{side}: " + ", ".join(f"{k}={len(v) if isinstance(v, list) else type(v).__name__}" for k, v in entry.items()))
        for key, value in entry.items():
            if isinstance(value, list) and value:
                print(f"  {side}.{key}[0] = {json.dumps(value[0], ensure_ascii=False)[:300]}")
    for key, value in relay.items():
        if any(word in key.lower() for word in ("rheb", "error", "score", "record")):
            print(f"relay.{key} = {json.dumps(value, ensure_ascii=False)[:400]}")

    season = dt.datetime.now(KST).year
    path = f"/statistics/categories/kbo/seasons/{season}/players?pageSize=100&playerType=PITCHER&teamCode={team_code}"
    status, body = get(path)
    print(f"{path}: HTTP {status}, {len(((body or {}).get('result') or {}).get('seasonPlayerStats') or [])} players")
    path = f"/statistics/categories/kbo/seasons/{season}/players?playerType=HITTER&teamCode={team_code}"
    status, body = get(path)
    stats = (((body or {}).get("result") or {}).get("seasonPlayerStats") or [])
    print(f"{path}: HTTP {status}, {len(stats)} players")
    if stats:
        sample = {k: v for k, v in stats[0].items() if k.startswith("hitter") or k in ("playerId", "playerName", "teamId", "backNumber")}
        print(json.dumps(sample, ensure_ascii=False)[:1500])

    # KBO 공식 홈페이지 1군 등록 현황 (앱의 KBORosterParser 와 같은 방식으로 읽어 본다)
    url = "https://www.koreabaseball.com/Player/RegisterAll.aspx"
    request = urllib.request.Request(url, headers={"User-Agent": HEADERS["User-Agent"]})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            html = response.read().decode("utf-8", "replace")
    except Exception as error:  # noqa: BLE001
        print(f"{url}: {error}")
        return
    import re
    table = re.search(r'<table class="tData tDays".*?</table>', html, re.S)
    print(f"{url}: {len(html)} bytes, table found={bool(table)}")
    if table:
        body = table.group(0)
        row_count = body.count('<th scope="row"')
        tr_count = len(re.findall(r"<tr[^>]*>", body))
        print(f"row headers: {row_count}, tr tags: {tr_count}")
        second = [m.start() for m in re.finditer(r'<th scope="row"', body)]
        if len(second) > 1:
            print("row2 raw: " + re.sub(r"\s+", " ", body[second[1] - 300:second[1] + 600]))
        else:
            print("row1 tail raw: " + re.sub(r"\s+", " ", body[-900:]))
        headers = re.findall(r'<th scope="col">(.*?)</th>', table.group(0))
        print(f"headers: {headers}")
        for row in re.findall(r'<tr>(.*?)</tr>', table.group(0), re.S):
            team = re.search(r'<th scope="row"[^>]*>(.*?)</th>', row, re.S)
            if not team:
                continue
            cells = re.findall(r'<td>(.*?)</td>', row, re.S)
            names = [re.findall(r'<li>(.*?)</li>', cell) for cell in cells]
            print(f"team {team.group(1)!r}: " + ", ".join(f"{len(n)}" for n in names) + f" | 투수 예시 {names[2][:3] if len(names) > 2 else None}")
    cancel = re.search(r'1군 말소 현황.*?</table>', html, re.S)
    if cancel:
        rows = re.findall(r'<td>\s*(.*?)</td>\s*<td>(.*?)</td>\s*<td>(.*?)</td>', cancel.group(0), re.S)
        print(f"말소 {len(rows)}명, 예시 {rows[:3]}")


def probe_kbo_player(player_ids):
    """KBO 공식 선수 기록 페이지의 연도별 팀 (팀 이력용). 네이버 선수 코드와 KBO playerId 가 같은지도 본다."""
    import re
    print("\n=== KBO 선수 연도별 기록 ===")
    for player_id, kind in player_ids:
        for page in ("Total.aspx", "Basic.aspx"):
            url = f"https://www.koreabaseball.com/Record/Player/{kind}Detail/{page}?playerId={player_id}"
            request = urllib.request.Request(url, headers={"User-Agent": HEADERS["User-Agent"]})
            try:
                with urllib.request.urlopen(request, timeout=15) as response:
                    html = response.read().decode("utf-8", "replace")
            except Exception as error:  # noqa: BLE001
                print(f"{url}: {error}")
                continue
            name = re.search(r'id="cphContents_cphContents_cphContents_playerProfile_lblName"[^>]*>(.*?)<', html)
            career = re.search(r'id="cphContents_cphContents_cphContents_playerProfile_lblCareer"[^>]*>(.*?)<', html)
            print(f"{url}: {len(html)} bytes, name={name.group(1) if name else None}, career={career.group(1) if career else None}")
            for table in re.findall(r"<table[^>]*>.*?</table>", html, re.S)[:3]:
                headers = [re.sub(r"<[^>]+>", "", h).strip() for h in re.findall(r"<th[^>]*>(.*?)</th>", table, re.S)]
                rows = []
                for row in re.findall(r"<tr[^>]*>(.*?)</tr>", table, re.S):
                    cells = [re.sub(r"<[^>]+>", "", c).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)]
                    if cells:
                        rows.append(cells[:4])
                print(f"  table headers={headers[:8]} rows={len(rows)} first={rows[:3]} last={rows[-2:]}")
            for marker in ("lblCareer", "연도별", "Total", "팀명"):
                print(f"  marker {marker!r}: {html.find(marker)}")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "kbo-player":
        # 오스틴(LG 타자), 임찬규(LG 투수), 박정우(KIA 타자), 대니엘(KT 투수)
        probe_kbo_player([("53123", "Hitter"), ("61101", "Pitcher"), ("67609", "Hitter"), ("56002", "Pitcher")])
        sys.exit(0)
    sys.exit(main())
