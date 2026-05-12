// PortBridge/Views/ServerListView.swift
import SwiftUI

struct ServerListView: View {
    @Bindable var vm: AppViewModel
    @State private var showAddSheet = false
    @State private var editingServer: Server? = nil

    var body: some View {
        List {
            // 포워딩 중 섹션
            if !vm.activeForwardings.isEmpty {
                Section {
                    ForEach(vm.activeForwardings, id: \.id) { fw in
                        activeRow(for: fw)
                    }
                } header: {
                    Text("포워딩 중")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }

            // 빈 상태
            if vm.serverSections.isEmpty {
                ContentUnavailableView(
                    "등록된 서버가 없습니다",
                    systemImage: "server.rack",
                    description: Text("'+' 버튼으로 SSH 서버를 추가하세요.")
                )
            }

            // 서버별 섹션
            ForEach(vm.serverSections) { section in
                ServerSectionView(
                    section: section,
                    activeForwardings: vm.activeForwardings,
                    onToggle: { port in
                        Task { await vm.toggleForwarding(serverId: section.server.id, for: port) }
                    },
                    onEdit: { editingServer = section.server },
                    onDelete: { vm.deleteServer(section.server) }
                )
            }
        }
        .safeAreaInset(edge: .top) {
            serverListHeader
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.activeForwardings.map(\.id))
        .sheet(isPresented: $showAddSheet) {
            AddServerSheet { server in vm.addServer(server) }
        }
        .sheet(item: $editingServer) { server in
            AddServerSheet(editing: server) { updated in vm.updateServer(updated) }
        }
    }

    @ViewBuilder
    private func activeRow(for fw: Forwarding) -> some View {
        if let section = vm.serverSections.first(where: { $0.server.id == fw.serverId }),
           let port = section.ports.first(where: { $0.port == fw.remotePort }) {
            ForwardingRowView(
                port: port,
                forwarding: fw,
                onToggle: { Task { await vm.toggleForwarding(serverId: fw.serverId, for: port) } }
            )
        }
    }

    private var serverListHeader: some View {
        HStack {
            Text("서버")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await vm.scanAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("전체 서버 포트 새로고침")

            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("서버 추가")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
