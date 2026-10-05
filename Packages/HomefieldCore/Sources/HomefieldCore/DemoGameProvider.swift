import Foundation

/// 실제 경기 없이 앱을 시험해 볼 수 있는 가상 경기.
/// relay 를 호출할 때마다 중계가 한 줄씩 진행된다.
public actor DemoGameProvider: GameDataProvider {
    public static let gameId = "demo-001"
    public static let home = Team(code: "DRM", name: "홈구장 드림즈")
    public static let away = Team(code: "VKG", name: "바이킹스")

    private let script: [(inning: Int, side: TeamSide, text: String)] = [
        (1, .away, "1번타자 강한별"),
        (1, .away, "1구 볼"),
        (1, .away, "2구 스트라이크"),
        (1, .away, "강한별 : 좌익수 플라이 아웃"),
        (1, .away, "2번타자 오세진"),
        (1, .away, "오세진 : 중견수 앞 1루타"),
        (1, .away, "3번타자 문태양"),
        (1, .away, "1구 볼"),
        (1, .away, "1루주자 오세진 : 도루로 2루까지 진루"),
        (1, .away, "문태양 : 헛스윙 삼진 아웃"),
        (1, .away, "4번타자 백도윤"),
        (1, .away, "백도윤 : 유격수 땅볼 아웃"),
        (1, .home, "1번타자 한결"),
        (1, .home, "1구 파울"),
        (1, .home, "한결 : 유격수 실책으로 출루"),
        (1, .home, "2번타자 서지후"),
        (1, .home, "1구 볼"),
        (1, .home, "2구 볼"),
        (1, .home, "3구 스트라이크"),
        (1, .home, "4구 볼"),
        (1, .home, "5구 볼"),
        (1, .home, "서지후 : 볼넷"),
        (1, .home, "1루주자 한결 : 2루까지 진루"),
        (1, .home, "3번타자 강두원"),
        (1, .home, "1구 스트라이크"),
        (1, .home, "강두원 : 좌중간 담장 넘어가는 홈런 (비거리: 125m)"),
        (1, .home, "2루주자 한결 : 홈인"),
        (1, .home, "1루주자 서지후 : 홈인"),
        (1, .home, "강두원 : 홈인"),
        (1, .home, "4번타자 곽민재"),
        (1, .home, "곽민재 : 우익수 플라이 아웃"),
        (1, .home, "5번타자 유태오"),
        (1, .home, "유태오 : 우익수 앞 1루타"),
        (1, .home, "6번타자 장우진"),
        (1, .home, "장우진 : 3루수 앞 땅볼로 병살타"),
        (1, .home, "1루주자 유태오 : 2루에서 포스아웃"),
        (2, .away, "투수 윤성현 : 투수 이세준 (으)로 교체"),
        (2, .away, "5번타자 한재희"),
        (2, .away, "한재희 : 몸에 맞는 볼"),
        (2, .away, "6번타자 고세혁"),
        (2, .away, "1루주자 한재희 : 도루실패 아웃 (포수->유격수 태그아웃)"),
        (2, .away, "고세혁 : 우중간 2루타"),
        (2, .away, "7번타자 최용구"),
        (2, .away, "2루주자 고세혁 : 폭투로 3루까지 진루"),
        (2, .away, "최용구 : 중견수 희생플라이 아웃"),
        (2, .away, "3루주자 고세혁 : 홈인"),
        (2, .away, "8번타자 남궁현"),
        (2, .away, "남궁현 : 좌익수 라인드라이브 아웃"),
    ]

    private var revealed = 0

    public init() {}

    public func games(on date: Date) async throws -> [GameSummary] {
        [summary()]
    }

    public func relay(gameId: String, inning: Int?) async throws -> RelaySnapshot {
        if inning == nil {
            revealed = min(revealed + 1, script.count)
            // 실제 중계처럼 타구 결과와 뒤따르는 홈인은 한꺼번에 들어온다
            while revealed < script.count, script[revealed].text.hasSuffix(": 홈인") {
                revealed += 1
            }
        }
        let visible = script.prefix(revealed).enumerated().filter { inning == nil || $0.element.inning == inning }
        let entries = visible.map { index, line in
            RelayEntry(
                id: "demo-\(index)",
                sequence: index,
                inning: line.inning,
                battingSide: line.side,
                text: line.text
            )
        }
        return RelaySnapshot(
            game: summary(),
            currentInning: script.prefix(revealed).last?.inning ?? 1,
            entries: entries,
            lineups: [
                .away: lineup(["강한별", "오세진", "문태양", "백도윤", "한재희", "고세혁", "최용구", "남궁현", "표정우"], team: Self.away),
                .home: lineup(["한결", "서지후", "강두원", "곽민재", "유태오", "장우진", "민경수", "도하람", "임준표"], team: Self.home),
            ],
            pitchers: [
                .away: [Player(id: "VKG-배준서", name: "배준서", teamCode: Self.away.code, backNumber: "21", position: "투수")],
                .home: [Player(id: "DRM-윤성현", name: "윤성현", teamCode: Self.home.code, backNumber: "18", position: "투수")],
            ]
        )
    }

    private func summary() -> GameSummary {
        let classifier = RelayTextClassifier()
        var score: [TeamSide: Int] = [.home: 0, .away: 0]
        var lines: [TeamSide: LineScore.Line] = [.home: LineScore.Line(), .away: LineScore.Line()]
        let hitKinds: Set<PlayKind> = [.single, .double, .triple, .homeRun]
        for line in script.prefix(revealed) {
            let kinds = classifier.classify(line.text)
            var current = lines[line.side] ?? LineScore.Line()
            while current.innings.count < line.inning { current.innings.append(0) }
            if kinds.contains(.run) {
                score[line.side, default: 0] += 1
                current.innings[line.inning - 1] = (current.innings[line.inning - 1] ?? 0) + 1
            }
            if kinds.contains(where: hitKinds.contains) { current.hits = (current.hits ?? 0) + 1 }
            lines[line.side] = current
            // 실책은 수비 팀 기록
            if kinds.contains(.error) {
                lines[line.side.opposite, default: LineScore.Line()].errors = (lines[line.side.opposite]?.errors ?? 0) + 1
            }
        }
        for side in [TeamSide.home, .away] {
            lines[side]?.runs = score[side]
            if lines[side]?.hits == nil { lines[side]?.hits = 0 }
            if lines[side]?.errors == nil { lines[side]?.errors = 0 }
        }
        let last = script.prefix(revealed).last
        let finished = revealed >= script.count
        return GameSummary(
            id: Self.gameId,
            home: Self.home,
            away: Self.away,
            homeScore: score[.home],
            awayScore: score[.away],
            status: finished ? .finished : .live,
            statusText: finished ? "데모 종료" : last.map { "\($0.inning)회\($0.side == .away ? "초" : "말")" } ?? "1회초",
            startTime: Date(),
            stadium: "홈구장 (데모)",
            lineScore: LineScore(away: lines[.away] ?? LineScore.Line(), home: lines[.home] ?? LineScore.Line())
        )
    }

    /// 타순대로 수비 위치를 붙인다
    private static let positions = ["중견수", "2루수", "우익수", "1루수", "3루수", "좌익수", "포수", "유격수", "지명타자"]

    private func lineup(_ names: [String], team: Team) -> [Player] {
        names.enumerated().map { index, name in
            Player(
                id: "\(team.code)-\(name)",
                name: name,
                teamCode: team.code,
                backNumber: String(index + 10),
                battingOrder: index + 1,
                position: Self.positions[index]
            )
        }
    }
}
