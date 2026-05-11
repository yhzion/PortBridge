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

            Button {
                Task { await vm.scan() }
            } label: {
                if vm.isScanning {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("검색 중…")
                    }
                } else {
                    Label("포트 검색", systemImage: "magnifyingglass")
                }
            }
            .disabled(vm.selectedHost == nil || vm.isScanning)

            Spacer()
        }
        .padding(.horizontal)
    }
}
