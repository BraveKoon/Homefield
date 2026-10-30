import AppIntents
import HomefieldCore
import SwiftUI
import UIKit
import WidgetKit

// MARK: - 설정 (위젯을 길게 눌러 팀을 고른다)

#if DEMO_BUILD
// 데모 빌드: 가상 팀만 고를 수 있다
enum WidgetTeam: String, AppEnum {
    case DRM, VKG

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "팀"

    static var caseDisplayRepresentations: [WidgetTeam: DisplayRepresentation] = [
        .DRM: "홈구장 드림즈", .VKG: "바이킹스",
    ]
}
#else
enum WidgetTeam: String, AppEnum {
    case LG, HT, SS, OB, LT, SK, HH, NC, KT, WO

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "팀"

    static var caseDisplayRepresentations: [WidgetTeam: DisplayRepresentation] = [
        .LG: "LG 트윈스", .HT: "KIA 타이거즈", .SS: "삼성 라이온즈", .OB: "두산 베어스", .LT: "롯데 자이언츠",
        .SK: "SSG 랜더스", .HH: "한화 이글스", .NC: "NC 다이노스", .KT: "KT 위즈", .WO: "키움 히어로즈",
    ]
}
#endif

struct SelectTeamIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "응원팀 경기"
    static var description = IntentDescription("응원팀의 오늘 경기 점수를 보여 줍니다. 팀을 비워 두면 앱에서 고른 응원팀을 따라갑니다.")

    /// 비워 두면 앱의 응원팀
    @Parameter(title: "팀 (비우면 내 응원팀)")
    var team: WidgetTeam?

    init() {}

    init(team: WidgetTeam?) {
        self.team = team
    }
}

// MARK: - 타임라인

struct TeamGameEntry: WidgetKit.TimelineEntry {
    let date: Date
    let teamCode: String?
    let result: TeamGameFinder.Result?
    /// 팀 코드 → 로고 PNG (위젯 뷰에서는 이미지를 받을 수 없어서 미리 받아 둔다)
    let logos: [String: Data]
    let failed: Bool
    /// 가을야구 테마 (앱 설정을 따른다)
    var isAutumn: Bool = AutumnStyle.isActive

    /// 팀을 고르지 않았을 때의 팀 (데모 빌드는 가상 팀)
    static var defaultTeam: String { BuildFlavor.isDemo ? "DRM" : "HT" }

    static func preview(teamCode: String = TeamGameEntry.defaultTeam) -> TeamGameEntry {
        let opponent: Team
        if BuildFlavor.isDemo {
            let code = teamCode == "DRM" ? "VKG" : "DRM"
            opponent = Team(code: code, name: AppTeams.name(for: code) ?? code)
        } else {
            opponent = Team(code: teamCode == "LG" ? "KT" : "LG", name: teamCode == "LG" ? "KT 위즈" : "LG 트윈스")
        }
        let game = GameSummary(
            id: "preview",
            home: Team(code: teamCode, name: AppTeams.name(for: teamCode) ?? teamCode),
            away: opponent,
            homeScore: 3,
            awayScore: 2,
            status: .live,
            statusText: "7회말",
            stadium: "광주"
        )
        return TeamGameEntry(date: Date(), teamCode: teamCode, result: .init(game: game, isToday: true), logos: [:], failed: false)
    }
}

struct TeamGameProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TeamGameEntry {
        .preview()
    }

    func snapshot(for configuration: SelectTeamIntent, in context: Context) async -> TeamGameEntry {
        if context.isPreview { return .preview(teamCode: configuration.team?.rawValue ?? SharedSettings.favoriteTeamCode ?? TeamGameEntry.defaultTeam) }
        return await entry(for: configuration)
    }

    func timeline(for configuration: SelectTeamIntent, in context: Context) async -> Timeline<TeamGameEntry> {
        let entry = await entry(for: configuration)
        let next = entry.failed
            ? Date().addingTimeInterval(15 * 60)
            : TeamGameFinder.nextRefresh(for: entry.result)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func entry(for configuration: SelectTeamIntent) async -> TeamGameEntry {
        let chosen = configuration.team?.rawValue ?? SharedSettings.favoriteTeamCode
        let code: String
        let provider: any GameDataProvider
        if BuildFlavor.isDemo {
            // 데모 빌드: 가상 경기(1회말 끝, 3 대 0)를 보여 준다. 일반 빌드에서 고른 실제 팀이 남아 있으면 가상 팀으로 바꾼다.
            code = chosen.flatMap { AppTeams.contains($0) ? $0 : nil } ?? TeamGameEntry.defaultTeam
            provider = DemoGameProvider(revealed: DemoGameProvider.midGameRevealed)
        } else if let chosen {
            code = chosen
            provider = NaverSportsProvider()
        } else {
            return TeamGameEntry(date: Date(), teamCode: nil, result: nil, logos: [:], failed: false)
        }
        do {
            let result = try await TeamGameFinder(provider: provider).find(teamCode: code)
            let codes = result.map { [$0.game.away.code, $0.game.home.code] } ?? [code]
            return TeamGameEntry(date: Date(), teamCode: code, result: result, logos: await Self.logos(for: codes), failed: false)
        } catch {
            return TeamGameEntry(date: Date(), teamCode: code, result: nil, logos: await Self.logos(for: [code]), failed: true)
        }
    }

    /// 네이버 스포츠 팀 로고를 받아 작게 줄인다 (위젯 메모리 제한)
    private static func logos(for codes: [String]) async -> [String: Data] {
        var result: [String: Data] = [:]
        // 데모 빌드는 로고를 받지 않는다
        for code in Set(codes) where !BuildFlavor.isDemo && KBOTeams.name(for: code) != nil {
            guard let url = URL(string: "https://sports-phinf.pstatic.net/team/kbo/default/\(code).png") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let image = UIImage(data: data),
                  let small = image.preparingThumbnail(of: CGSize(width: 120, height: 120 * image.size.height / max(image.size.width, 1))),
                  let png = small.pngData()
            else { continue }
            result[code] = png
        }
        return result
    }
}

// MARK: - 위젯

struct TeamGameWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: TeamGameWidgetKind.kind, intent: SelectTeamIntent.self, provider: TeamGameProvider()) { entry in
            TeamGameWidgetView(entry: entry)
        }
        .configurationDisplayName("응원팀 경기")
        .description("앱에서 고른 응원팀의 오늘 경기 점수와 다음 경기를 보여 줍니다. 다른 팀은 위젯을 길게 눌러 고르세요.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TeamGameWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TeamGameEntry

    var body: some View {
        content
            .environment(\.isAutumn, entry.isAutumn)
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular: RectangularView(entry: entry)
        case .accessoryInline: InlineView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        default: SmallView(entry: entry)
        }
    }

    @ViewBuilder
    private var background: some View {
        if family == .accessoryRectangular || family == .accessoryInline {
            AccessoryWidgetBackground()
        } else {
            let theme = TeamTheme.forTeam(entry.teamCode)
            ZStack {
                LinearGradient(colors: [theme.primary.vivid.opacity(0.95), theme.secondary, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                // 은은한 야구공 실밥
                Circle()
                    .stroke(.white.opacity(0.07), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
                    .frame(width: 220, height: 220)
                    .offset(x: 90, y: -70)
                Circle()
                    .stroke(.white.opacity(0.05), lineWidth: 18)
                    .frame(width: 260, height: 260)
                    .offset(x: -120, y: 110)
                if entry.isAutumn {
                    // 가을야구: 아래쪽 노을빛 + 단풍잎
                    LinearGradient(colors: [.clear, AutumnStyle.orange.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                    FallingLeaves(count: family == .systemSmall ? 5 : 8, animated: false, opacity: 0.45, scale: 0.75)
                }
            }
        }
    }
}

// MARK: - 크기별 화면

private struct SmallView: View {
    let entry: TeamGameEntry

    var body: some View {
        if let result = entry.result {
            let game = result.game
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(entry: entry, compact: true)
                Spacer(minLength: 4)
                HStack(spacing: 0) {
                    LogoBadge(code: game.away.code, data: entry.logos[game.away.code], size: 38)
                    Spacer(minLength: 2)
                    if game.status == .scheduled || game.status == .cancelled {
                        Text("VS")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        ScorePair(game: game, size: 26)
                    }
                    Spacer(minLength: 2)
                    LogoBadge(code: game.home.code, data: entry.logos[game.home.code], size: 38)
                }
                HStack {
                    Text(TeamTheme.shortName(for: game.away.code))
                    Spacer()
                    Text(TeamTheme.shortName(for: game.home.code))
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 4)
                .padding(.top, 4)
                Spacer(minLength: 4)
                GameStatusLine(result: result)
            }
            .foregroundStyle(.white)
        } else {
            EmptyStateView(entry: entry)
        }
    }
}

private struct MediumView: View {
    let entry: TeamGameEntry

    var body: some View {
        if let result = entry.result {
            let game = result.game
            VStack(spacing: 8) {
                WidgetHeader(entry: entry, compact: false)
                HStack(spacing: 0) {
                    TeamStack(team: game.away, data: entry.logos[game.away.code], favorite: entry.teamCode == game.away.code)
                    VStack(spacing: 6) {
                        if game.status == .scheduled || game.status == .cancelled {
                            Text(game.startTime.map(Self.timeText) ?? "VS")
                                .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                        } else {
                            ScorePair(game: game, size: 40)
                        }
                        StatusChip(game: game)
                    }
                    .frame(minWidth: 120)
                    TeamStack(team: game.home, data: entry.logos[game.home.code], favorite: entry.teamCode == game.home.code)
                }
                .frame(maxHeight: .infinity)
            }
            .foregroundStyle(.white)
        } else {
            EmptyStateView(entry: entry)
        }
    }

    static func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

private struct RectangularView: View {
    let entry: TeamGameEntry

    var body: some View {
        if let result = entry.result {
            let game = result.game
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "baseball.fill").font(.caption2)
                    Text(statusText(result))
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(TeamTheme.shortName(for: game.away.code))
                    Spacer(minLength: 0)
                    Text(score(game.awayScore, game))
                }
                .font(.headline.weight(.bold))
                HStack(spacing: 6) {
                    Text(TeamTheme.shortName(for: game.home.code))
                    Spacer(minLength: 0)
                    Text(score(game.homeScore, game))
                }
                .font(.headline.weight(.bold))
            }
            .monospacedDigit()
        } else {
            VStack(alignment: .leading) {
                Label("홈구장", systemImage: "baseball.fill").font(.headline)
                Text(entry.teamCode == nil ? "앱에서 응원팀 선택" : "예정된 경기 없음").font(.caption)
            }
        }
    }

    private func score(_ value: Int?, _ game: GameSummary) -> String {
        game.status == .scheduled ? "" : value.map(String.init) ?? "-"
    }
}

private struct InlineView: View {
    let entry: TeamGameEntry

    var body: some View {
        if let result = entry.result {
            let game = result.game
            let away = TeamTheme.shortName(for: game.away.code)
            let home = TeamTheme.shortName(for: game.home.code)
            if game.status == .scheduled {
                Text("⚾︎ \(away) vs \(home) \(statusText(result))")
            } else {
                Text("⚾︎ \(away) \(game.awayScore ?? 0):\(game.homeScore ?? 0) \(home) · \(statusText(result))")
            }
        } else {
            Text("⚾︎ 홈구장")
        }
    }
}

// MARK: - 부품

/// "MY TEAM · 오늘" / 다음 경기 날짜, 오른쪽에 구장
private struct WidgetHeader: View {
    let entry: TeamGameEntry
    let compact: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(entry.result?.isToday == false ? "NEXT GAME" : "MY TEAM")
                .font(.system(size: 10, weight: .black))
                .tracking(0.8)
            Spacer(minLength: 0)
            if let game = entry.result?.game {
                if !compact, let stadium = game.stadium {
                    Label(stadium, systemImage: "mappin.and.ellipse")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                if game.status == .live {
                    LiveDot()
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct LiveDot: View {
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(.white).frame(width: 5, height: 5)
            Text("LIVE").font(.system(size: 9, weight: .black))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.red, in: Capsule())
    }
}

/// 원정 : 홈 점수, 이기는 쪽은 밝게
private struct ScorePair: View {
    let game: GameSummary
    let size: CGFloat

    var body: some View {
        let away = game.awayScore ?? 0
        let home = game.homeScore ?? 0
        HStack(spacing: size * 0.25) {
            Text("\(away)").opacity(away >= home ? 1 : 0.6)
            Text(":").font(.system(size: size * 0.6, weight: .bold, design: .rounded)).opacity(0.5)
            Text("\(home)").opacity(home >= away ? 1 : 0.6)
        }
        .font(.system(size: size, weight: .black, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// 위젯 아래 한 줄: "7회말" / "오늘 18:30 · 창원" / "10.22(목) 18:30" / "경기 종료"
private struct GameStatusLine: View {
    let result: TeamGameFinder.Result

    var body: some View {
        HStack(spacing: 4) {
            if result.game.status == .live {
                Circle().fill(Color.red).frame(width: 6, height: 6)
            }
            Text(statusText(result))
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.16), in: Capsule())
    }
}

private struct StatusChip: View {
    let game: GameSummary

    var body: some View {
        let live = game.status == .live
        HStack(spacing: 4) {
            if live {
                Circle().fill(.white).frame(width: 5, height: 5)
                Text("LIVE").font(.system(size: 10, weight: .black))
            }
            Text(chipText).font(.caption.weight(.bold)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(live ? Color.red : Color.white.opacity(0.18), in: Capsule())
    }

    private var chipText: String {
        switch game.status {
        case .live: game.statusText ?? "경기 중"
        case .scheduled:
            game.startTime.map { $0.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated)) } ?? "경기 전"
        default: game.status.displayName
        }
    }
}

/// 로고 + 팀 이름 (중간 크기)
private struct TeamStack: View {
    let team: Team
    let data: Data?
    let favorite: Bool

    var body: some View {
        VStack(spacing: 6) {
            LogoBadge(code: team.code, data: data, size: 50)
                .overlay(alignment: .topTrailing) {
                    if favorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.red, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            Text(team.name)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 흰 원 안에 팀 로고. 로고를 못 받았으면 팀 색 동그라미.
private struct LogoBadge: View {
    @Environment(\.isAutumn) private var isAutumn
    let code: String
    let data: Data?
    let size: CGFloat

    var body: some View {
        logo.overlay(alignment: .bottomTrailing) {
            if isAutumn { AutumnLeafBadge(size: size) }
        }
    }

    @ViewBuilder
    private var logo: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(size * 0.15)
                .frame(width: size, height: size)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        } else {
            TeamDot(code: code, size: size)
        }
    }
}

private struct EmptyStateView: View {
    let entry: TeamGameEntry

    var body: some View {
        VStack(spacing: 8) {
            if let code = entry.teamCode {
                LogoBadge(code: code, data: entry.logos[code], size: 44)
                Text(entry.failed ? "경기 정보를 받지 못했어요" : "일주일 안에 경기가 없어요")
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "baseball.fill")
                    .font(.system(size: 30))
                Text("앱에서 응원팀을\n골라 주세요")
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func statusText(_ result: TeamGameFinder.Result) -> String {
    let game = result.game
    switch game.status {
    case .live:
        return game.statusText ?? "경기 중"
    case .scheduled:
        guard let start = game.startTime else { return "경기 전" }
        let time = start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let day = result.isToday ? "오늘" : start.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated))
        return [day + " " + time, game.stadium].compactMap { $0 }.joined(separator: " · ")
    case .finished:
        return "경기 종료"
    case .cancelled:
        return "경기 취소"
    case .unknown:
        return game.statusText ?? "-"
    }
}

#Preview(as: .systemMedium) {
    TeamGameWidget()
} timeline: {
    TeamGameEntry.preview()
}
