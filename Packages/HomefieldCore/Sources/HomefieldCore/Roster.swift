import Foundation

/// 한 팀의 1군 엔트리 (가장 최근 경기의 라인업 + 벤치 + 투수)
public struct TeamRoster: Codable, Hashable, Sendable {
    public enum Group: String, Codable, CaseIterable, Sendable {
        case pitcher, catcher, infielder, outfielder, other

        public var displayName: String {
            switch self {
            case .pitcher: "투수"
            case .catcher: "포수"
            case .infielder: "내야수"
            case .outfielder: "외야수"
            case .other: "기타"
            }
        }

        public init(position: String?) {
            let text = position ?? ""
            if text.contains("투") {
                self = .pitcher
            } else if text.contains("포") {
                self = .catcher
            } else if ["1루", "2루", "3루", "유격", "내야"].contains(where: text.contains) {
                self = .infielder
            } else if ["좌익", "중견", "우익", "외야"].contains(where: text.contains) {
                self = .outfielder
            } else {
                self = .other
            }
        }
    }

    public var teamCode: String
    public var players: [Player]
    /// 이 명단을 가져온 경기
    public var gameId: String
    public var gameDate: Date?
    public var updatedAt: Date

    public init(teamCode: String, players: [Player], gameId: String, gameDate: Date?, updatedAt: Date = Date()) {
        self.teamCode = teamCode
        self.players = players
        self.gameId = gameId
        self.gameDate = gameDate
        self.updatedAt = updatedAt
    }

    public func contains(name: String) -> Bool {
        players.contains { $0.name == name }
    }

    public struct Section: Hashable, Sendable, Identifiable {
        public var group: Group
        public var players: [Player]
        public var id: Group { group }
    }

    /// 투수, 포수, 내야수, 외야수 순으로 묶는다
    public var grouped: [Section] {
        Group.allCases.compactMap { group -> Section? in
            let members = players
                .filter { Group(position: $0.position) == group }
                .sorted { ($0.backNumber.flatMap(Int.init) ?? 999, $0.name) < ($1.backNumber.flatMap(Int.init) ?? 999, $1.name) }
            return members.isEmpty ? nil : Section(group: group, players: members)
        }
    }

    /// 중계 한 번에서 양 팀 엔트리를 만든다. 선수 코드로 중복을 없애고, 먼저 나온 정보(라인업)를 우선한다.
    public static func rosters(from snapshot: RelaySnapshot) -> [TeamRoster] {
        guard let game = snapshot.game else { return [] }
        return [TeamSide.away, .home].compactMap { side in
            var seen = Set<String>()
            var players: [Player] = []
            let all = (snapshot.lineups[side] ?? []) + (snapshot.pitchers[side] ?? []) + (snapshot.benches[side] ?? [])
            for player in all where seen.insert(player.id).inserted {
                var player = player
                // 경기 중 위치(대타 등)가 아닌 원래 포지션이 나중 목록에 있으면 그걸 쓴다
                if Group(position: player.position) == .other,
                   let better = all.first(where: { $0.id == player.id && Group(position: $0.position) != .other }) {
                    player.position = better.position
                }
                if player.backNumber == nil {
                    player.backNumber = all.first { $0.id == player.id && $0.backNumber != nil }?.backNumber
                }
                players.append(player)
            }
            // 엔트리가 없고 라인업만 있으면 1군 전체가 아니므로 쓰지 않는다
            guard !(snapshot.benches[side] ?? []).isEmpty else { return nil }
            return TeamRoster(
                teamCode: game.team(for: side).code,
                players: players,
                gameId: game.id,
                gameDate: game.startTime
            )
        }
    }
}

/// 팀마다 가장 최근 경기의 엔트리로 1군 명단을 모은다 (등록·말소가 경기 엔트리에 반영된다)
public struct RosterCollector: Sendable {
    public var provider: any GameDataProvider
    public var lookbackDays: Int
    public var teamCodes: Set<String>

    public init(provider: any GameDataProvider, lookbackDays: Int = 10, teamCodes: Set<String> = Set(KBOTeams.all.map(\.code))) {
        self.provider = provider
        self.lookbackDays = lookbackDays
        self.teamCodes = teamCodes
    }

    public func collect(today: Date = Date(), calendar: Calendar = .current) async -> [String: TeamRoster] {
        var result: [String: TeamRoster] = [:]
        for back in 0...lookbackDays {
            guard result.count < teamCodes.count,
                  let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let games = try? await provider.games(on: day)
            else { continue }
            // 경기 시작 전에는 엔트리가 없을 수 있으니 진행 중·끝난 경기만
            let candidates = games.filter { game in
                (game.status == .live || game.status == .finished)
                    && (result[game.home.code] == nil || result[game.away.code] == nil)
                    && (teamCodes.contains(game.home.code) || teamCodes.contains(game.away.code))
            }
            for game in candidates {
                guard let snapshot = try? await provider.relay(gameId: game.id, inning: nil) else { continue }
                var withGame = snapshot
                if withGame.game == nil { withGame.game = game }
                for roster in TeamRoster.rosters(from: withGame) where result[roster.teamCode] == nil && teamCodes.contains(roster.teamCode) {
                    result[roster.teamCode] = roster
                }
            }
        }
        return result
    }
}
