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
                    Picker("응원팀", selection: $settings.favoriteTeamCode) {
                        Text("없음").tag(String?.none)
                        ForEach(library.teamCodes, id: \.self) { code in
                            Text(library.teamName(for: code)).tag(Optional(code))
                        }
                    }
                    Picker("노래 재생", selection: $settings.songScope) {
                        ForEach(AppSettings.SongScope.allCases) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                } header: {
                    Text("응원")
                }

                Section {
                    Stepper(value: $settings.broadcastDelay, in: 0...120, step: 1) {
                        Text("방송 싱크: \(Int(settings.broadcastDelay))초 늦게")
                    }
                    Stepper(value: $settings.walkUpDuration, in: 5...60, step: 5) {
                        Text("등장곡 재생: \(Int(settings.walkUpDuration))초")
                    }
                    Stepper(value: $settings.pollInterval, in: 2...30, step: 1) {
                        Text("중계 확인 주기: \(Int(settings.pollInterval))초")
                    }
                } header: {
                    Text("타이밍")
                } footer: {
                    Text("문자중계가 TV보다 빠르면 '방송 싱크'를 늘려서 화면과 맞춰 주세요.")
                }

                Section("나레이션") {
                    Toggle("타자 소개 (\"3번 타자, 홍길동!\")", isOn: $settings.announceBatter)
                    VStack(alignment: .leading) {
                        Text("말하기 속도")
                        Slider(value: $settings.speechRate, in: 0.3...0.65)
                    }
                    NavigationLink("상황별 나레이션") {
                        NarrationSettingsView()
                    }
                }

                Section {
                    Toggle("데모 경기 사용", isOn: $settings.useDemo)
                } header: {
                    Text("테스트")
                } footer: {
                    Text("실제 경기가 없을 때 가상 경기로 등장곡과 나레이션을 시험해 볼 수 있습니다.")
                }

                Section {
                    Text("경기 데이터는 네이버 스포츠 문자중계를 사용합니다. 등장곡·응원가는 저작권 때문에 앱에 포함되어 있지 않으니, Apple Music이나 직접 가진 음악 파일로 지정해 주세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
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
