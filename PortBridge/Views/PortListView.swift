import SwiftUI

struct PortListView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("포트 또는 프로세스 검색", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(vm.filteredPorts) { port in
                ForwardingRowView(
                    port: port,
                    forwarding: vm.forwardings.first {
                        $0.remotePort == port.port && $0.host == vm.selectedHost?.name
                    },
                    onToggle: { Task { await vm.toggleForwarding(for: port) } }
                )
            }
        }
    }
}
