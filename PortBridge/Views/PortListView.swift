import SwiftUI

struct PortListView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.ports.isEmpty {
                ContentUnavailableView(
                    vm.selectedHost == nil ? "서버를 선택해주세요" : "열려있는 포트가 없습니다",
                    systemImage: vm.selectedHost == nil ? "server.rack" : "magnifyingglass",
                    description: Text(vm.selectedHost == nil
                        ? "위에서 SSH 서버를 선택하고 '포트 검색'을 눌러보세요."
                        : "이 서버에서 1000~65535 범위에 리스닝 중인 포트가 없습니다.")
                )
                .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("포트 번호나 프로세스 이름으로 찾기", text: $vm.searchText)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)

                HStack {
                    Text(verbatim: "검색된 포트 \(vm.filteredPorts.count)개 / 총 \(vm.ports.count)개")
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
                        isActive: false,
                        onToggle: { Task { await vm.toggleForwarding(for: port) } }
                    )
                }
            }
        }
    }
}
