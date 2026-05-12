import SwiftUI

struct HostPickerView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .foregroundStyle(.secondary)

            Picker("리모트 서버", selection: $vm.selectedHost) {
                Text("서버를 선택하세요").tag(SSHHost?.none)
                ForEach(vm.hosts) { host in
                    Text(host.name).tag(SSHHost?.some(host))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            .onChange(of: vm.selectedHost) { _, newHost in
                vm.lastError = nil
                vm.ports = []
                guard newHost != nil else { return }
                Task { await vm.scan() }
            }

            Button {
                Task { await vm.scan() }
            } label: {
                if vm.isScanning {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("검색 중…")
                    }
                } else if vm.ports.isEmpty {
                    Label("포트 검색", systemImage: "magnifyingglass")
                } else {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
            }
            .disabled(vm.selectedHost == nil || vm.isScanning)
            .help(vm.ports.isEmpty ? "선택한 서버의 포트를 스캔합니다" : "포트 목록을 다시 불러옵니다")

            Spacer()
        }
        .padding(.horizontal)
    }
}
