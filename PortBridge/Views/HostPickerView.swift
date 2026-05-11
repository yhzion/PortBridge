import SwiftUI

struct HostPickerView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        HStack {
            Picker("호스트", selection: $vm.selectedHost) {
                Text("선택…").tag(SSHHost?.none)
                ForEach(vm.hosts) { host in
                    Text(host.name).tag(SSHHost?.some(host))
                }
            }
            .frame(maxWidth: 200)

            Button("스캔") {
                Task { await vm.scan() }
            }
            .disabled(vm.selectedHost == nil || vm.isScanning)

            if vm.isScanning {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}
