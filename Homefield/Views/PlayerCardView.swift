import HomefieldCore
import SwiftUI

extension CardGrade {
    /// 등급 색 (1성 회색 → 5성 금색)
    var color: Color {
        switch self {
        case .one: Color(hex: 0x8E8E93)
        case .two: Color(hex: 0x34A853)
        case .three: Color(hex: 0x2E7CF6)
        case .four: Color(hex: 0x9B4DE0)
        case .five: Color(hex: 0xF2B33D)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 컴프야 같은 선수 카드 한 장
struct PlayerCardView: View {
    let card: PlayerCard
    var width: CGFloat = 150
    /// 처음 뽑은 카드면 NEW
    var isNew = false

    private var height: CGFloat { width * 1.45 }

    var body: some View {
        let theme = TeamTheme.forTeam(card.teamCode)
        VStack(spacing: 0) {
            header
            photo(theme: theme)
            footer
        }
        .frame(width: width, height: height)
        .background {
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .fill(theme.gradient)
        }
        .overlay {
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .stroke(card.grade.gradient, lineWidth: card.grade == .five ? 3 : 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: width * 0.09, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isNew {
                Text("NEW")
                    .font(.system(size: width * 0.07, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, width * 0.04)
                    .padding(.vertical, width * 0.015)
                    .background(Color.yellow, in: Capsule())
                    .padding(width * 0.04)
            }
        }
        .shadow(color: card.grade.color.opacity(card.grade == .five ? 0.7 : 0.35), radius: width * 0.07, y: width * 0.03)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.grade.displayName) \(card.name), \(TeamTheme.shortName(for: card.teamCode))")
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text(card.grade.stars)
                .font(.system(size: width * 0.085, weight: .black))
                .foregroundStyle(card.grade == .five ? .black : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            Text("\(card.season)")
                .font(.system(size: width * 0.065, weight: .heavy))
                .foregroundStyle(card.grade == .five ? .black.opacity(0.7) : .white.opacity(0.8))
        }
        .padding(.horizontal, width * 0.07)
        .padding(.vertical, width * 0.04)
        .background(card.grade.gradient)
    }

    private func photo(theme: TeamTheme) -> some View {
        ZStack {
            RemoteImage(url: SportsImageURL.player(card.playerId), contentMode: .fill) {
                Image(systemName: "person.fill")
                    .font(.system(size: width * 0.3))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(width: width, height: width * 0.78)
            .clipped()

            // 아래쪽을 어둡게 해서 이름이 읽히게
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        }
        .frame(width: width, height: width * 0.78)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                TeamBadge(code: card.teamCode, size: width * 0.17)
                if let backNumber = card.backNumber {
                    Text("#\(backNumber)")
                        .font(.system(size: width * 0.07, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .padding(width * 0.05)
        }
    }

    private var footer: some View {
        VStack(spacing: width * 0.02) {
            Text(card.name)
                .font(.system(size: width * 0.12, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text([card.position, card.kind == .pitcher ? "투수" : "타자"].compactMap { $0 }.first ?? "")
                .font(.system(size: width * 0.065, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            if let line = statLine {
                Text(line)
                    .font(.system(size: width * 0.062, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, width * 0.04)
                    .padding(.vertical, width * 0.015)
                    .background(.white.opacity(0.16), in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, width * 0.05)
        .padding(.vertical, width * 0.045)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 카드 아래 한 줄 기록 (그해 공식 기록 그대로)
    private var statLine: String? {
        guard let stats = card.stats else { return nil }
        let items = stats.displayItems
        func value(_ label: String) -> String? {
            items.first { $0.label == label }?.value
        }
        let parts: [String?]
        switch stats.kind {
        case .batter:
            parts = [value("타율").map { "타율 \($0)" }, value("홈런").map { "\($0)홈런" }, value("타점").map { "\($0)타점" }]
        case .pitcher:
            parts = [value("평균자책").map { "ERA \($0)" }, value("승").map { "\($0)승" }, value("세이브").flatMap { $0 == "0" ? nil : "\($0)세이브" }]
        }
        let line = parts.compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }
}

/// 카드가 없는 자리 (도감에서 아직 못 뽑은 선수, 라인업 빈 칸)
struct EmptyCardSlot: View {
    var width: CGFloat = 150
    var label: String?

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: width * 0.18, weight: .light))
                    if let label {
                        Text(label)
                            .font(.system(size: width * 0.08, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(width * 0.08)
            }
            .frame(width: width, height: width * 1.45)
    }
}
