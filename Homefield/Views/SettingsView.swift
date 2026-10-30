import HomefieldCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SongLibrary.self) private var library

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ScrollView {
                            TeamPickerGrid(selection: $settings.favoriteTeamCode)
                                .padding(16)
                            Button("응원팀 없음") { settings.favoriteTeamCode = nil }
                                .padding(.bottom, 24)
                        }
                        .background { ThemedBackground() }
                        .navigationTitle("응원팀")
                    } label: {
                        FavoriteTeamHeader(code: settings.favoriteTeamCode, name: settings.favoriteTeamCode.map(library.teamName(for:)))
                    }
                    .listRowBackground(FavoriteTeamHeader.background(for: settings.favoriteTeamCode))
                }

                // 데모 빌드는 로그인·동기화를 끈다 (실제 계정 데이터를 건드리지 않는다)
                if !BuildFlavor.isDemo {
                    AccountSection()
                }

                Section {
                    Picker(selection: $settings.songScope) {
                        ForEach(AppSettings.SongScope.allCases) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    } label: {
                        SettingsLabel("노래 재생", systemImage: "music.note", color: .pink)
                    }
                    Picker(selection: $settings.autumnMode) {
                        ForEach(AutumnBaseball.Mode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    } label: {
                        SettingsLabel("가을야구 테마", systemImage: "leaf.fill", color: AutumnStyle.orange)
                    }
                } header: {
                    Text("응원")
                } footer: {
                    Text("가을야구 테마를 켜면 앱 배경과 홈 화면 위젯에 단풍잎이 떨어지고, 구단 로고에 단풍잎이 붙습니다. 기본은 포스트시즌 기간(10월 1일 ~ 11월 15일)에만 켜집니다.")
                }

                Section {
                    Toggle(isOn: $settings.liveActivityEnabled) {
                        SettingsLabel("잠금화면 실시간 중계", systemImage: "iphone.gen3.radiowaves.left.and.right", color: .red)
                    }
                    SettingsLabel("홈 화면 위젯", systemImage: "square.grid.2x2.fill", color: .indigo)
                        .badge("길게 눌러 추가")
                } header: {
                    Text("위젯")
                } footer: {
                    Text("경기 화면을 열어 두면 잠금화면 알림 영역과 다이내믹 아일랜드에 점수판과 최근 중계가 나옵니다. 앱이 백그라운드에 있어도 계속 갱신하도록 소리 없는 오디오를 함께 켭니다. 홈 화면을 길게 눌러 '홈구장' 위젯을 추가하고, 위젯을 길게 눌러 팀을 고르면 그 팀 경기 점수가 나옵니다.")
                }

                Section {
                    Stepper(value: $settings.broadcastDelay, in: 0...120, step: 1) {
                        SettingsLabel("방송 싱크 \(Int(settings.broadcastDelay))초 늦게", systemImage: "tv.fill", color: .blue)
                    }
                    Stepper(value: $settings.walkUpDuration, in: 5...60, step: 5) {
                        SettingsLabel("등장곡 \(Int(settings.walkUpDuration))초", systemImage: "figure.baseball", color: .orange)
                    }
                    Stepper(value: $settings.pollInterval, in: 2...30, step: 1) {
                        SettingsLabel("중계 확인 \(Int(settings.pollInterval))초마다", systemImage: "arrow.triangle.2.circlepath", color: .teal)
                    }
                } header: {
                    Text("타이밍")
                } footer: {
                    Text("문자중계가 TV보다 빠르면 '방송 싱크'를 늘려서 화면과 맞춰 주세요.")
                }

                Section("나레이션") {
                    Toggle(isOn: $settings.announceBatter) {
                        SettingsLabel("타자 소개 (\"3번 타자, 홍길동!\")", systemImage: "megaphone.fill", color: .green)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsLabel("말하기 속도", systemImage: "speedometer", color: .purple)
                        HStack {
                            Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                            Slider(value: $settings.speechRate, in: 0.3...0.65)
                            Image(systemName: "hare.fill").foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        NarrationSettingsView()
                    } label: {
                        SettingsLabel("상황별 나레이션", systemImage: "text.bubble.fill", color: .mint)
                    }
                }

                if !BuildFlavor.isDemo {
                    Section {
                        Toggle(isOn: $settings.useDemo) {
                            SettingsLabel("데모 경기 사용", systemImage: "play.rectangle.fill", color: .gray)
                        }
                    } header: {
                        Text("테스트")
                    } footer: {
                        Text("실제 경기가 없을 때 가상 경기로 등장곡과 나레이션을 시험해 볼 수 있습니다.")
                    }
                }

                Section {
                    Text("경기 데이터는 네이버 스포츠 문자중계를 사용합니다. 등장곡·응원가는 저작권 때문에 앱에 포함되어 있지 않으니, Apple Music이나 직접 가진 음악 파일로 지정해 주세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .themedBackground()
            .modifier(AccountDialogs())
            .navigationTitle("설정")
        }
    }
}

/// 설정 첫 줄: 응원팀 로고와 이름을 크게
private struct FavoriteTeamHeader: View {
    let code: String?
    let name: String?

    var body: some View {
        HStack(spacing: 14) {
            if let code {
                TeamBadge(code: code, size: 54)
            } else {
                Image(systemName: "baseball.fill")
                    .font(.system(size: 30))
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.2), in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("MY TEAM")
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .opacity(0.8)
                Text(name ?? "응원팀 고르기")
                    .font(.title3.weight(.heavy))
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.vertical, 6)
    }

    static func background(for code: String?) -> some View {
        TeamTheme.forTeam(code).gradient
    }
}

/// 색 네모 아이콘 + 글자 (iOS 설정 앱처럼)
struct SettingsLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

struct NarrationSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(PlayKind.allCases) { kind in
                    NarrationRow(kind: kind)
                }
            } footer: {
                Text("문구를 비워 두면 기본 문구를 사용합니다. 홈런 뒤 득점은 '투런 홈런!'처럼 합쳐서 읽어요.")
            }
        }
        .navigationTitle("상황별 나레이션")
    }
}

private struct NarrationRow: View {
    @Environment(AppSettings.self) private var settings
    let kind: PlayKind

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(isOn: Binding(
                get: { settings.enabledPlays.contains(kind) },
                set: { enabled in
                    if enabled { settings.enabledPlays.insert(kind) } else { settings.enabledPlays.remove(kind) }
                }
            )) {
                Text("\(kind.emoji) \(kind.displayName)")
            }
            TextField(kind.defaultNarration, text: Binding(
                get: { settings.customPhrases[kind] ?? "" },
                set: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    settings.customPhrases[kind] = trimmed.isEmpty ? nil : text
                }
            ))
            .font(.callout)
            .textFieldStyle(.roundedBorder)
            .disabled(!settings.enabledPlays.contains(kind))
        }
    }
}
