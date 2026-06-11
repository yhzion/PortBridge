import SwiftUI

/// 설정 씬(⌘,) — 메뉴바 메뉴에 있던 설정류(로그인 시 시작·Dock·업데이트)를 이전받는다.
/// 메뉴는 동작(토글/열기/종료) 표면으로, 설정은 표준 Settings 윈도우로 분리.
struct SettingsView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var preferences = viewModel.preferences

        Form {
            Section {
                Toggle(
                    String(localized: "settings.launchAtLogin", defaultValue: "로그인 시 시작"),
                    isOn: $preferences.launchAtLogin
                )
                Toggle(
                    String(localized: "settings.showInDock", defaultValue: "Dock에 표시"),
                    isOn: $preferences.showInDock
                )
            } header: {
                Text(String(localized: "settings.general.header", defaultValue: "일반"))
            }

            Section {
                Toggle(
                    String(localized: "settings.updates.autoCheck", defaultValue: "자동으로 업데이트 확인"),
                    isOn: $preferences.automaticUpdateCheckEnabled
                )
                HStack {
                    Button {
                        Task { await viewModel.updates.checkNow(manual: true) }
                    } label: {
                        Text(String(localized: "settings.updates.checkNow", defaultValue: "지금 업데이트 확인…"))
                    }
                    .disabled(viewModel.updates.phase == .checking)

                    if viewModel.updates.phase == .checking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } header: {
                Text(String(localized: "settings.updates.header", defaultValue: "업데이트"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}

#Preview {
    SettingsView()
        .environment(AppViewModel())
}
