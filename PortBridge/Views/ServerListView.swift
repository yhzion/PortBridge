// PortBridge/Views/ServerListView.swift
import SwiftUI

struct ServerListView: View {
    @Bindable var vm: AppViewModel
    @State private var showAddSheet = false
    @State private var editingServer: Server? = nil

    var body: some View {
        Group {
            if vm.serverSections.isEmpty && vm.activeForwardings.isEmpty {
                emptyStateView
            } else {
                serverList
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

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("등록된 서버가 없습니다")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                showAddSheet = true
            } label: {
                Label("서버 추가", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var serverList: some View {
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
