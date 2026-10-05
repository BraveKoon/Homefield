import HomefieldCore
import SwiftUI

/// 직관 인증과 등급
struct AttendanceView: View {
    @Environment(AttendanceStore.self) private var attendance
    @Environment(\.teamTheme) private var theme

    @State private var checking = false
    @State private var message: (text: String, success: Bool)?
    @State private var showingTiers = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TierCard(
                        tier: attendance.tier,
                        count: attendance.count,
                        progress: attendance.progress,
                        remaining: attendance.remainingToNext,
                        theme: theme
                    )
                    .listRowInsets(EdgeInsets())
                    .onTapGesture { showingTiers = true }
                }

                Section {
                    Button {
                        Task { await checkIn() }
                    } label: {
                        HStack {
                            Label("지금 직관 인증하기", systemImage: "location.circle.fill")
                                .font(.headline)
                            Spacer()
                            if checking { ProgressView() }
                        }
                    }
                    .disabled(checking)
                    if let message {
                        Label(message.text, systemImage: message.success ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(message.success ? .green : .orange)
                    }
                } footer: {
                    Text("경기 날 야구장 안(구장 중심 500m 이내)에서 누르면 인증됩니다. 구장마다 하루 한 번. 위치는 인증할 때만 확인하고, 좌표는 저장하지 않고 구장 이름만 이 기기에 남깁니다.")
                }

                Section("구장 도장") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                        ForEach(Stadiums.all) { stadium in
                            StadiumStamp(stadium: stadium, visits: attendance.visits(to: stadium), theme: theme)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("직관 기록") {
                    if attendance.checkIns.isEmpty {
                        Text("아직 인증한 직관이 없어요. 야구장에 가면 인증해 보세요!")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(attendance.checkIns) { checkIn in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(checkIn.gameTitle ?? checkIn.stadium?.name ?? "직관")
                                .font(.headline)
                            HStack {
                                Text(checkIn.date, format: .dateTime.year().month().day().weekday())
                                if let stadium = checkIn.stadium {
                                    Text("· \(stadium.name)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { attendance.checkIns[$0] }.forEach(attendance.remove)
                    }
                }
            }
            .themedBackground()
            .navigationTitle("직관")
            .sheet(isPresented: $showingTiers) {
                NavigationStack { TierGuideView(count: attendance.count) }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func checkIn() async {
        checking = true
        defer { checking = false }
        do {
            let before = attendance.tier
            let result = try await attendance.checkIn(schedule: NaverSportsProvider())
            let stadium = result.stadium?.name ?? "야구장"
            var text = "\(stadium) 직관 인증 완료! (\(attendance.count)회)"
            if attendance.tier > before {
                text += " 등급이 \(attendance.tier.emoji) \(attendance.tier.title)(으)로 올랐어요!"
            }
            message = (text, true)
        } catch {
            message = (error.localizedDescription, false)
        }
    }
}

private struct TierCard: View {
    let tier: FanTier
    let count: Int
    let progress: Double
    let remaining: Int?
    let theme: TeamTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.emoji).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text("내 등급").font(.caption).opacity(0.8)
                    Text(tier.title).font(.largeTitle.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("직관").font(.caption).opacity(0.8)
                    Text("\(count)회").font(.title2.bold().monospacedDigit())
                }
            }
            ProgressView(value: progress)
                .tint(.white)
            if let next = tier.next, let remaining {
                Text("\(next.emoji) \(next.title)까지 \(remaining)회 남았어요")
                    .font(.footnote)
                    .opacity(0.9)
            } else {
                Text("최고 등급이에요. 이 구역의 감독님!")
                    .font(.footnote)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.gradient)
        .accessibilityElement(children: .combine)
        .accessibilityHint("등급 안내 보기")
    }
}

private struct StadiumStamp: View {
    let stadium: Stadium
    let visits: Int
    let theme: TeamTheme

    var body: some View {
        let visited = visits > 0
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .strokeBorder(visited ? theme.primary : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: visited ? [] : [4]))
                    .background(Circle().fill(visited ? theme.primary.opacity(0.15) : .clear))
                Image(systemName: visited ? "checkmark.seal.fill" : "baseball")
                    .font(.title2)
                    .foregroundStyle(visited ? theme.primary : .secondary)
            }
            .frame(width: 56, height: 56)
            Text(stadium.aliases.first ?? stadium.name)
                .font(.caption.bold())
            Text(visited ? "\(visits)회" : "아직")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stadium.name) \(visited ? "\(visits)회 방문" : "방문 안 함")")
    }
}

private struct TierGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let count: Int

    var body: some View {
        List(FanTier.allCases, id: \.self) { tier in
            HStack {
                Text(tier.emoji).font(.title2)
                VStack(alignment: .leading) {
                    Text(tier.title).font(.headline)
                    Text(tier == .rookie ? "처음 시작" : "직관 \(tier.threshold)회 이상")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if FanTier.tier(forCheckIns: count) == tier {
                    Text("지금").font(.caption.bold()).foregroundStyle(.tint)
                }
            }
        }
        .navigationTitle("등급 안내")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("닫기") { dismiss() }
            }
        }
    }
}
