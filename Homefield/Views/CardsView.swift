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
    @State private var isEnteringCode = false

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
                                    CardPackRow(kind: kind, store: store) { open(kind, count: $0) }
                                }
                            }
                        }
                    }

                    section("코드 사용") {
                        Button {
                            isEnteringCode = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "gift.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(Color.pink.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("코드 입력").font(.headline)
                                    Text("받은 코드를 넣으면 포인트를 받습니다")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .cardStyle(padding: 12)
                        }
                        .buttonStyle(.plain)
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
            PackOpeningView(kind: kind, store: store)
        }
        .sheet(isPresented: $isEnteringCode) {
            CouponView(store: store)
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

    private func open(_ kind: CardPackKind, count: Int = 1) {
        guard store.open(kind, count: count) != nil else {
            notice = kind == .basic
                ? "오늘 기본 카드팩은 이미 열었어요. 내일 다시 받을 수 있어요."
                : "포인트가 \(kind.cost * count - store.points) 모자라요. 경기를 보거나 직관을 인증해 포인트를 모아 주세요."
            return
        }
        opening = kind
    }
}

/// 코드를 넣어 포인트를 받는 창
private struct CouponView: View {
    @Environment(\.dismiss) private var dismiss
    let store: CardStore

    @State private var code = ""
    @State private var message: String?
    @State private var isError = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("코드", text: $code)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(use)
                } footer: {
                    if let message {
                        Label(message, systemImage: isError ? "exclamationmark.triangle" : "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isError ? .red : .green)
                    } else {
                        Text("받은 코드를 그대로 넣어 주세요. 코드마다 한 번만 쓸 수 있습니다.")
                    }
                }

                Section {
                    Button("사용하기", action: use)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    LabeledContent("지금 포인트", value: "\(store.points) P")
                }
            }
            .navigationTitle("코드 사용")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func use() {
        do {
            let coupon = try store.redeem(code: code)
            isError = false
            message = "\(coupon.points) 포인트를 받았어요!"
            code = ""
            focused = false
        } catch {
            isError = true
            message = error.localizedDescription
        }
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
                    Text("\(String(pool.season)) 도감 \(Int((completion * 100).rounded()))% · 전체 \(pool.cards.count)종")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    ForEach(CardReward.recurring) { reward in
                        Label("\(reward.displayName) +\(reward.points)", systemImage: icon(for: reward))
                            .font(.caption2.weight(.bold))
                    }
                }
                Label("라인업 선수가 안타·홈런·도루·삼진을 하면 포인트", systemImage: "star.fill")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white.opacity(0.9))
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
        case .welcome: "gift.fill"
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
    /// (한 번에 열 카드팩 수)
    let action: (Int) -> Void

    private var bulk: Int { CardCollection.bulkCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            }
            HStack(spacing: 8) {
                // 포인트로 사는 팩은 연속 뽑기도 할 수 있다 (기본 카드팩은 하루 한 번)
                if kind != .basic {
                    Button { action(bulk) } label: {
                        VStack(spacing: 1) {
                            Text("\(bulk)연속")
                                .font(.subheadline.weight(.bold))
                            Text("\(kind.cost * bulk)P")
                                .font(.caption2.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(kind.topGrade.color)
                    .disabled(!store.canOpen(kind, count: bulk))
                }
                Button { action(1) } label: {
                    VStack(spacing: 1) {
                        Text("1회")
                            .font(.subheadline.weight(.bold))
                        Text(priceTitle)
                            .font(.caption2.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(store.canOpen(kind) ? kind.topGrade.color : .gray)
            }
        }
        .cardStyle(padding: 12)
    }

    private var priceTitle: String {
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
    let store: CardStore

    @State private var revealed = 0
    @State private var notice: String?

    private var cards: [PlayerCard] { store.lastOpened }
    /// 연속 뽑기처럼 카드가 많으면 한꺼번에 펼쳐 보여 준다
    private var isBulk: Bool { cards.count > 3 }
    private var bulk: Int { CardCollection.bulkCount }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(kind.displayName)
                    .font(.title2.weight(.black))
                if isBulk {
                    Text("\(cards.count / kind.cardCount)팩 · 카드 \(cards.count)장")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .foregroundStyle(.white)

            if isBulk {
                bulkResult
            } else {
                Spacer()
                singleResult
                Spacer()
            }

            footer
        }
        .padding(20)
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
        .onAppear(perform: reveal)
        .onChange(of: cards.map(\.id)) { _, _ in reveal() }
    }

    /// 1~3장은 탭해서 한 장씩 뒤집는다
    private var singleResult: some View {
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
    }

    /// 연속 뽑기는 등급 높은 카드부터 격자로
    private var bulkResult: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(CardGrade.allCases.reversed()) { grade in
                    let count = cards.filter { $0.grade == grade }.count
                    if count > 0 {
                        Text("\(grade.displayName) \(count)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(grade.color, in: Capsule())
                            .foregroundStyle(grade == .five ? .black : .white)
                    }
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 10) {
                    ForEach(Array(sortedCards.enumerated()), id: \.offset) { _, card in
                        PlayerCardView(card: card, width: 88, isNew: store.isSingleCopy(card))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if revealed < cards.count {
                Text("탭해서 카드 확인")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                HStack(spacing: 8) {
                    // 연속 뽑기를 결제(한 번 더) 버튼 앞에 둔다
                    if kind != .basic {
                        Button { draw(count: bulk) } label: {
                            VStack(spacing: 1) {
                                Text("\(bulk)연속").font(.subheadline.weight(.bold))
                                Text("\(kind.cost * bulk)P").font(.caption2.monospacedDigit())
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .disabled(!store.canOpen(kind, count: bulk))
                    }
                    Button { draw(count: 1) } label: {
                        VStack(spacing: 1) {
                            Text("한 번 더").font(.subheadline.weight(.bold))
                            Text(againPrice).font(.caption2.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(!store.canOpen(kind))
                }
                HStack(spacing: 12) {
                    Text("\(store.points) P")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                    Button("닫기") { dismiss() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            if let notice {
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var againPrice: String {
        if kind == .basic {
            return store.canOpenDailyPack ? "무료" : "내일"
        }
        return "\(kind.cost)P"
    }

    private var sortedCards: [PlayerCard] {
        CardSort(field: .grade, isDescending: true).apply(to: cards)
    }

    private func draw(count: Int) {
        guard store.open(kind, count: count) != nil else {
            notice = kind == .basic
                ? "오늘 기본 카드팩은 이미 열었어요."
                : "포인트가 \(kind.cost * count - store.points) 모자라요."
            return
        }
        notice = nil
    }

    /// 1장짜리 팩과 연속 뽑기는 바로 보여 주고, 2~3장은 탭해서 뒤집는다
    private func reveal() {
        revealed = cards.count == 1 || isBulk ? cards.count : 0
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

    @AppStorage("cardSortField") private var sortField = CardSortField.grade.rawValue
    @AppStorage("cardSortDescending") private var isDescending = true

    private var sort: CardSort {
        CardSort(field: CardSortField(rawValue: sortField) ?? .grade, isDescending: isDescending)
    }

    var body: some View {
        NavigationStack {
            List {
                if store.collection.lineupCards[slot] != nil {
                    Button("이 칸 비우기", role: .destructive) {
                        store.setLineup(nil, at: slot)
                        dismiss()
                    }
                }
                ForEach(store.collection.owned(sortedBy: sort)) { card in
                    Button {
                        store.setLineup(card.id, at: slot)
                        dismiss()
                    } label: {
                        CardPickerRow(
                            card: card,
                            copies: store.collection.count(of: card.id),
                            registeredSlot: store.collection.lineupSlot(of: card.id),
                            currentSlot: slot
                        )
                    }
                }
            }
            .navigationTitle("\(slot + 1)번 타자")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SortMenu(sortField: $sortField, isDescending: $isDescending)
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

/// 정렬 기준(등급·팀·가나다)과 높은순·낮은순을 고른다
private struct SortMenu: View {
    @Binding var sortField: String
    @Binding var isDescending: Bool

    private var field: CardSortField {
        CardSortField(rawValue: sortField) ?? .grade
    }

    var body: some View {
        Menu {
            Picker("정렬 기준", selection: $sortField) {
                ForEach(CardSortField.allCases) { item in
                    Text(item.displayName).tag(item.rawValue)
                }
            }
            Picker("순서", selection: $isDescending) {
                Text(field.orderName(descending: true)).tag(true)
                Text(field.orderName(descending: false)).tag(false)
            }
        } label: {
            Label(CardSort(field: field, isDescending: isDescending).displayName, systemImage: "arrow.up.arrow.down")
                .font(.footnote.weight(.semibold))
        }
    }
}

/// 라인업에 넣을 카드 한 줄. 이미 라인업에 있으면 '등록됨'.
private struct CardPickerRow: View {
    let card: PlayerCard
    let copies: Int
    let registeredSlot: Int?
    let currentSlot: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(card.grade.stars)
                .font(.caption.weight(.black))
                .foregroundStyle(card.grade.color)
                .frame(width: 44, alignment: .leading)
            TeamBadge(code: card.teamCode, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name).font(.body.weight(.semibold))
                Text(TeamTheme.shortName(for: card.teamCode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if copies > 1 {
                Text("×\(copies)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let registeredSlot {
                Text(registeredSlot == currentSlot ? "이 칸" : "\(registeredSlot + 1)번 등록됨")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(registeredSlot == currentSlot ? Color.accentColor : Color.secondary.opacity(0.25), in: Capsule())
                    .foregroundStyle(registeredSlot == currentSlot ? .white : .secondary)
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
    @State private var isConfirmingRefund = false
    @State private var refunded: Int?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 104), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            refundBar
            filters
            if let pool = store.pool {
                let cards = filtered(pool.cards)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cards) { card in
                        if store.collection.has(card.id) {
                            let mine = store.collection.cards[card.id] ?? card
                            let spare = store.spareCount(of: card.id)
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
                                .contextMenu {
                                    if spare > 0 {
                                        Button {
                                            refunded = store.refund(card.id, count: 1)
                                        } label: {
                                            Label("1장 환불 +\(mine.grade.refundPoints)P", systemImage: "arrow.uturn.left.circle")
                                        }
                                        if spare > 1 {
                                            Button {
                                                refunded = store.refund(card.id, count: spare)
                                            } label: {
                                                Label("중복 \(spare)장 환불 +\(mine.grade.refundPoints * spare)P", systemImage: "tray.full")
                                            }
                                        }
                                    } else {
                                        Text("중복 카드만 환불할 수 있어요")
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
        .confirmationDialog(
            "중복 카드를 모두 환불할까요?",
            isPresented: $isConfirmingRefund,
            titleVisibility: .visible
        ) {
            Button("환불 +\(store.totalRefund)P") { refunded = store.refundAllSpares() }
            Button("그만두기", role: .cancel) {}
        } message: {
            Text("도감이 비지 않게 카드마다 한 장은 남깁니다. 응원 라인업에 넣은 카드도 그대로 남습니다.")
        }
        .alert("환불", isPresented: Binding(get: { refunded != nil }, set: { if !$0 { refunded = nil } })) {
            Button("확인") { refunded = nil }
        } message: {
            Text(refunded.map { "\($0) 포인트를 받았어요." } ?? "")
        }
    }

    /// 중복 카드 환불 (등급이 높을수록 많이 돌려받는다)
    @ViewBuilder
    private var refundBar: some View {
        let total = store.totalRefund
        if total > 0 {
            Button {
                isConfirmingRefund = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.left.circle.fill")
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("중복 카드 \(store.collection.spares.reduce(0) { $0 + store.spareCount(of: $1.id) })장 환불")
                            .font(.subheadline.weight(.bold))
                        Text("5성 150P · 4성 60P · 3성 25P · 2성 10P · 1성 5P")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("+\(total)P")
                        .font(.subheadline.weight(.black).monospacedDigit())
                        .foregroundStyle(.pink)
                }
                .cardStyle(padding: 12)
            }
            .buttonStyle(.plain)
        }
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
