import HomefieldCore
import SwiftUI

/// 카드 탭: 카드팩 열기, 응원 라인업, 도감
struct CardsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SongLibrary.self) private var library
    @Environment(AttendanceStore.self) private var attendance
    @Environment(CardStore.self) private var store

    @State private var opening: CardPackKind?
    @State private var lineupSlot: LineupSlot?
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WalletHeader(points: store.points, collection: store.collection, pool: store.pool)

                    if store.pool == nil {
                        PoolMissingCard(error: library.rosterError, isLoading: library.isRefreshingRosters)
                    } else {
                        section("카드팩") {
                            VStack(spacing: 10) {
                                ForEach(CardPackKind.allCases) { kind in
                                    CardPackRow(kind: kind, store: store) { open(kind) }
                                }
                            }
                        }
                    }

                    section("응원 라인업") {
                        LineupStrip(store: store) { lineupSlot = LineupSlot(index: $0) }
                    }

                    section("도감") {
                        CollectionBrowser(store: store, favorite: settings.favoriteTeamCode)
                    }
                }
                .padding(16)
            }
            .background { ThemedBackground() }
            .navigationTitle("카드")
            .refreshable { await library.refreshRosters(force: true) }
        }
        .task {
            await library.refreshRosters()
            store.refreshPool(library: library)
            store.awardDailyVisit()
            store.syncCheckIns(attendance.checkIns)
        }
        .onChange(of: library.rostersUpdatedAt) { _, _ in store.refreshPool(library: library) }
        .onChange(of: attendance.checkIns.count) { _, _ in store.syncCheckIns(attendance.checkIns) }
        .sheet(item: $opening) { kind in
            PackOpeningView(kind: kind, cards: store.lastOpened, store: store)
        }
        .sheet(item: $lineupSlot) { slot in
            LineupPickerView(slot: slot.index, store: store)
        }
        .alert("카드팩", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("확인") { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.heavy))
            content()
        }
    }

    private func open(_ kind: CardPackKind) {
        guard store.open(kind) != nil else {
            notice = kind == .basic
                ? "오늘 기본 카드팩은 이미 열었어요. 내일 다시 받을 수 있어요."
                : "포인트가 \(kind.cost - store.points) 모자라요. 경기를 보거나 직관을 인증해 포인트를 모아 주세요."
            return
        }
        opening = kind
    }
}

/// 라인업에서 고른 칸 (sheet 에 넘기려면 Identifiable 이어야 한다)
private struct LineupSlot: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - 머리말

private struct WalletHeader: View {
    let points: Int
    let collection: CardCollection
    let pool: CardPool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text("\(points) P")
                        .font(.title2.weight(.black).monospacedDigit())
                } icon: {
                    Image(systemName: "baseball.circle.fill")
                        .font(.title2)
                }
                Spacer()
                Text("카드 \(collection.owned.count)종")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)

            if let pool {
                let completion = collection.completion(of: pool)
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: completion)
                        .tint(.white)
                    Text("\(pool.season) 도감 \(Int((completion * 100).rounded()))% · 전체 \(pool.cards.count)종")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            HStack(spacing: 12) {
                ForEach(CardReward.allCases) { reward in
                    Label("\(reward.displayName) +\(reward.points)", systemImage: icon(for: reward))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            TeamTheme.default.gradient
                .overlay(Color.black.opacity(0.15))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func icon(for reward: CardReward) -> String {
        switch reward {
        case .dailyVisit: "sun.max.fill"
        case .watchGame: "tv.fill"
        case .checkIn: "sportscourt.fill"
        }
    }
}

private struct PoolMissingCard: View {
    let error: String?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                Label("1군 명단을 받고 있어요…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
            } else {
                Label(error ?? "1군 명단을 받아야 카드를 만들 수 있어요.", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                Text("아래로 당겨 새로고침해 주세요. 카드 등급은 그해 공식 기록으로 정해집니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}

// MARK: - 카드팩

private struct CardPackRow: View {
    let kind: CardPackKind
    let store: CardStore
    let action: () -> Void

    var body: some View {
        let available = store.canOpen(kind)
        HStack(spacing: 14) {
            PackArt(kind: kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.displayName)
                    .font(.headline)
                Text(kind.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(kind.oddsText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: action) {
                Text(buttonTitle)
                    .font(.subheadline.weight(.bold))
                    .frame(minWidth: 62)
            }
            .buttonStyle(.borderedProminent)
            .tint(available ? kind.topGrade.color : .gray)
        }
        .cardStyle(padding: 12)
    }

    private var buttonTitle: String {
        if kind == .basic {
            return store.canOpenDailyPack ? "무료" : "내일"
        }
        return "\(kind.cost)P"
    }
}

private extension CardPackKind {
    /// 그 팩에서 나올 수 있는 가장 높은 등급 (색으로 쓴다)
    var topGrade: CardGrade {
        odds.keys.max() ?? .one
    }
}

private struct PackArt: View {
    let kind: CardPackKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(kind.topGrade.gradient)
            Image(systemName: kind == .basic ? "shippingbox.fill" : "sparkles")
                .font(.title3)
                .foregroundStyle(kind.topGrade == .five ? .black : .white)
        }
        .frame(width: 46, height: 62)
        .shadow(color: kind.topGrade.color.opacity(0.4), radius: 5, y: 2)
    }
}

/// 카드팩을 열면 한 장씩 뒤집어 본다
private struct PackOpeningView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: CardPackKind
    let cards: [PlayerCard]
    let store: CardStore

    @State private var revealed = 0

    var body: some View {
        VStack(spacing: 20) {
            Text(kind.displayName)
                .font(.title2.weight(.black))
                .foregroundStyle(.white)

            Spacer()

            HStack(spacing: 12) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    Group {
                        if index < revealed {
                            PlayerCardView(card: card, width: cardWidth, isNew: store.isSingleCopy(card))
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        } else {
                            CardBack(width: cardWidth)
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.45), value: revealed)

            Spacer()

            if revealed < cards.count {
                Text("탭해서 카드 확인")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Button("닫기") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [.black, highlight.color.opacity(0.45), .black], startPoint: .top, endPoint: .bottom)
                // 높은 등급이 나오면 가운데가 환해진다
                if revealed == cards.count, highlight >= .four {
                    RadialGradient(
                        colors: [highlight.color.opacity(0.55), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 320
                    )
                }
            }
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if revealed < cards.count { revealed += 1 }
        }
        .onAppear {
            // 1장짜리 팩은 바로 보여 준다
            if cards.count == 1 { revealed = 1 }
        }
    }

    private var cardWidth: CGFloat {
        cards.count > 1 ? 104 : 190
    }

    /// 이번에 나온 가장 높은 등급
    private var highlight: CardGrade {
        cards.map(\.grade).max() ?? .one
    }
}

private struct CardBack: View {
    let width: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .fill(TeamTheme.default.gradient)
            Image(systemName: "baseball.fill")
                .font(.system(size: width * 0.3))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(width: width, height: width * 1.45)
    }
}

// MARK: - 응원 라인업

private struct LineupStrip: View {
    let store: CardStore
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<CardCollection.lineupSize, id: \.self) { slot in
                        Button { onSelect(slot) } label: {
                            VStack(spacing: 4) {
                                if let card = store.collection.lineupCards[slot] {
                                    PlayerCardView(card: card, width: 92)
                                } else {
                                    EmptyCardSlot(width: 92, label: "\(slot + 1)번")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            Text("라인업에 넣은 선수가 타석에 서면 경기 화면에 카드가 뜹니다. 카드 등급 합 \(store.collection.lineupPower)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LineupPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let slot: Int
    let store: CardStore

    var body: some View {
        NavigationStack {
            List {
                if store.collection.lineupCards[slot] != nil {
                    Button("이 칸 비우기", role: .destructive) {
                        store.setLineup(nil, at: slot)
                        dismiss()
                    }
                }
                ForEach(store.collection.owned) { card in
                    Button {
                        store.setLineup(card.id, at: slot)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(card.grade.stars)
                                .font(.caption.weight(.black))
                                .foregroundStyle(card.grade.color)
                                .frame(width: 44, alignment: .leading)
                            TeamBadge(code: card.teamCode, size: 28)
                            Text(card.name).font(.body.weight(.semibold))
                            Spacer()
                            if store.collection.count(of: card.id) > 1 {
                                Text("×\(store.collection.count(of: card.id))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(slot + 1)번 타자")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .overlay {
                if store.collection.owned.isEmpty {
                    ContentUnavailableView("아직 카드가 없어요", systemImage: "rectangle.on.rectangle", description: Text("카드팩을 열어 카드를 모아 주세요."))
                }
            }
        }
    }
}

// MARK: - 도감

private struct CollectionBrowser: View {
    let store: CardStore
    let favorite: String?

    @State private var team: String?
    @State private var grade: CardGrade?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 104), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            filters
            if let pool = store.pool {
                let cards = filtered(pool.cards)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cards) { card in
                        if store.collection.has(card.id) {
                            let mine = store.collection.cards[card.id] ?? card
                            PlayerCardView(card: mine, width: 104)
                                .overlay(alignment: .bottomTrailing) {
                                    let count = store.collection.count(of: card.id)
                                    if count > 1 {
                                        Text("×\(count)")
                                            .font(.caption2.weight(.black).monospacedDigit())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(.black.opacity(0.6), in: Capsule())
                                            .foregroundStyle(.white)
                                            .padding(5)
                                    }
                                }
                        } else {
                            LockedCard(card: card, width: 104)
                        }
                    }
                }
                if cards.isEmpty {
                    Text("조건에 맞는 카드가 없어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { if team == nil { team = favorite } }
    }

    private var filters: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("전체 팀", selected: team == nil) { team = nil }
                    ForEach(KBOTeams.all, id: \.code) { item in
                        chip(TeamTheme.shortName(for: item.code), selected: team == item.code) { team = item.code }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("전체 등급", selected: grade == nil) { grade = nil }
                    ForEach(CardGrade.allCases.reversed()) { item in
                        chip(item.displayName, selected: grade == item, color: item.color) { grade = item }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, color: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? AnyShapeStyle(color) : AnyShapeStyle(.regularMaterial), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func filtered(_ cards: [PlayerCard]) -> [PlayerCard] {
        cards.filter { card in
            (team == nil || card.teamCode == team) && (grade == nil || card.grade == grade)
        }
    }
}

/// 아직 못 뽑은 카드 (이름만 보여 준다)
private struct LockedCard: View {
    let card: PlayerCard
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
            .fill(.regularMaterial)
            .frame(width: width, height: width * 1.45)
            .overlay {
                VStack(spacing: 6) {
                    Text(card.grade.stars)
                        .font(.system(size: width * 0.08, weight: .black))
                        .foregroundStyle(card.grade.color.opacity(0.6))
                        .lineLimit(1)
                    Image(systemName: "questionmark")
                        .font(.system(size: width * 0.2, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(card.name)
                        .font(.system(size: width * 0.095, weight: .bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(TeamTheme.shortName(for: card.teamCode))
                        .font(.system(size: width * 0.07, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(width * 0.06)
            }
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                    .stroke(.secondary.opacity(0.3), lineWidth: 1)
            }
    }
}
