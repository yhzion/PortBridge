import SwiftUI

struct PortListView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("포트 번호나 프로세스 이름으로 찾기", text: $vm.searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            if vm.ports.isEmpty {
                ContentUnavailableView(
                    "검색된 포트가 없습니다",
                    systemImage: "wifi.slash",
                    description: Text("위에서 서버를 선택하고 '포트 검색'을 눌러보세요.")
                )
            } else {
                HStack {
                    Text(verbatim: "리모트에서 열려있는 포트 \(vm.filteredPorts.count)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
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
}
