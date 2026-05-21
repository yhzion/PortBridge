// PortBridge/Views/ServerListView.swift
import SwiftUI

struct ServerListView: View {
    @Bindable var vm: AppViewModel
    @State private var showAddSheet = false
    @State private var editingServer: Server?
    @State private var pendingDelete: Server?
    @FocusState private var isSearchFocused: Bool

    private var isDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func activeForwardingCount(for serverId: UUID) -> Int {
        vm.activeForwardings.filter { $0.serverId == serverId }.count
    }

    var body: some View {
        Group {
            if vm.serverSections.isEmpty && vm.activeForwardings.isEmpty {
                emptyStateView
            } else if isSearching && !hasSearchMatches {
                noSearchResultsView
            } else {
                serverList
            }
        }
        .safeAreaInset(edge: .top) {
            if !vm.serverSections.isEmpty {
                allServersHeader
            }
        }
        .safeAreaInset(edge: .top) {
            serverListHeader
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.activeForwardings.map(\.id))
        .sheet(isPresented: $showAddSheet) {
            AddServerSheet(
                isDuplicate: { user, host, port in vm.isDuplicateServer(user: user, host: host, port: port) }
            ) { server in
                vm.addServer(server)
            }
        }
        .sheet(item: $editingServer) { server in
            AddServerSheet(
                editing: server,
                isDuplicate: { user, host, port in
                    vm.isDuplicateServer(user: user, host: host, port: port, excluding: server.id)
                }
            ) { updated in
                Task { await vm.updateServer(updated) }
            }
        }
        .confirmationDialog(
            "서버 삭제",
            isPresented: isDeletePresented,
            presenting: pendingDelete
        ) { server in
            Button("삭제", role: .destructive) {
                vm.deleteServer(server)
                pendingDelete = nil
            }
            Button("취소", role: .cancel) {
                pendingDelete = nil
            }
        } message: { server in
            let label = server.name ?? server.host
            let active = activeForwardingCount(for: server.id)
            if active > 0 {
                Text(verbatim: "'\(label)'을(를) 삭제하면 활성 포워딩 \(active)개가 종료됩니다. 이 동작은 되돌릴 수 없습니다.")
            } else {
                Text("'\(label)'을(를) 삭제하시겠습니까? 이 동작은 되돌릴 수 없습니다.")
            }
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

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("'\(vm.searchText)'에 일치하는 결과가 없습니다")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button("검색어 지우기") {
                vm.searchText = ""
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleActiveForwardings: [Forwarding] {
        vm.activeForwardings.filter { fw in
            guard let section = vm.serverSections.first(where: { $0.server.id == fw.serverId }),
                  let port = section.ports.first(where: { $0.port == fw.remotePort }) else {
                return vm.searchText.isEmpty
            }
            return vm.matches(port)
        }
    }

    private var isSearching: Bool {
        !vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasSearchMatches: Bool {
        if !visibleActiveForwardings.isEmpty { return true }
        return vm.serverSections.contains { section in
            section.ports.contains(where: { vm.matches($0) })
        }
    }

    private var serverList: some View {
        List {
            // 포워딩 중 섹션
            if !visibleActiveForwardings.isEmpty {
                Section {
                    ForEach(visibleActiveForwardings, id: \.id) { fw in
                        activeRow(for: fw)
                    }
                } header: {
                    ActiveSectionHeader(
                        count: visibleActiveForwardings.count,
                        onStopAll: { vm.stopAllActiveForwardings() }
                    )
                    .padding(.vertical, 2)
                }
            }

            // 서버별 섹션
            Section {
                ForEach(vm.serverSections) { section in
                    ServerSectionView(
                        section: section,
                        activeForwardings: vm.activeForwardings,
                        matches: { vm.matches($0) },
                        onToggle: { port in
                            Task { await vm.toggleForwarding(serverId: section.server.id, for: port) }
                        },
                        onEdit: { editingServer = section.server },
                        onDelete: { pendingDelete = section.server },
                        isFavorite: { port in vm.isFavorite(serverId: section.server.id, port: port.port) },
                        onFavoriteToggle: { port in vm.toggleFavorite(serverId: section.server.id, port: port.port) }
                    )
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 28)
    }

    @ViewBuilder
    private func activeRow(for fw: Forwarding) -> some View {
        if let section = vm.serverSections.first(where: { $0.server.id == fw.serverId }),
           let port = section.ports.first(where: { $0.port == fw.remotePort }) {
            ForwardingRowView(
                port: port,
                forwarding: fw,
                serverDisplayName: vm.serverDisplayName(for: fw.serverId),
                onToggle: { Task { await vm.toggleForwarding(serverId: fw.serverId, for: port) } },
                isFavorite: vm.isFavorite(serverId: fw.serverId, port: port.port),
                onFavoriteToggle: { vm.toggleFavorite(serverId: fw.serverId, port: port.port) }
            )
        }
    }

    private var allServersHeader: some View {
        AllServersSectionHeader(
            count: vm.serverSections.count,
            allExpanded: vm.allExpanded,
            onToggleAll: {
                vm.toggleAllExpanded()
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var serverListHeader: some View {
        HStack(spacing: 8) {
            if vm.serverSections.isEmpty {
                Text("서버를 추가하세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("포트 번호나 프로세스 이름으로 찾기", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .controlSize(.small)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(
                                isSearchFocused ? Color.PB.inputBorderFocused : Color.PB.inputBorder,
                                lineWidth: isSearchFocused ? 1.5 : 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isSearchFocused)
                if !vm.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("검색어 지우기")
                }
            }

            Spacer(minLength: 4)

            Button {
                Task { await vm.scanAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("전체 서버 포트 새로고침 (⌘R)")
            .accessibilityLabel("전체 서버 포트 새로고침")
            .keyboardShortcut("r", modifiers: .command)

            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("서버 추가 (⌘N)")
            .accessibilityLabel("서버 추가")
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
