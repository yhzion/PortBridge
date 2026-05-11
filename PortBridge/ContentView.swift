import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 12) {
            HostPickerView(vm: vm)
            Divider()
            if vm.hosts.isEmpty {
                ContentUnavailableView(
                    "등록된 SSH 호스트가 없습니다",
                    systemImage: "network.slash",
                    description: Text(vm.lastError ?? "~/.ssh/config에 Host 항목을 추가하세요.")
                )
                .frame(maxHeight: .infinity)
            } else {
                PortListView(vm: vm)
            }
            if let err = vm.lastError, !vm.hosts.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .frame(minWidth: 360, idealWidth: 420, minHeight: 360, idealHeight: 480)
        .frame(maxHeight: .infinity, alignment: .top)
        .task { vm.loadHosts() }
        .sheet(item: Binding(
            get: { vm.pendingPortConflict },
            set: { vm.pendingPortConflict = $0 }
        )) { conflict in
            PortConflictSheet(conflict: conflict) { newPort in
                Task { await vm.resolveConflict(with: newPort) }
            }
        }
    }
}

struct PortConflictSheet: View {
    let conflict: PortConflict
    let onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var localPortText: String

    init(conflict: PortConflict, onConfirm: @escaping (Int) -> Void) {
        self.conflict = conflict
        self.onConfirm = onConfirm
        _localPortText = State(initialValue: String(conflict.attemptedLocal + 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "로컬 포트 \(conflict.attemptedLocal)이(가) 사용 중입니다")
                .font(.headline)
            Text(verbatim: "다른 로컬 포트를 입력하세요. 리모트는 \(conflict.host):\(conflict.remotePort).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("로컬 포트", text: $localPortText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("연결") {
                    if let port = Int(localPortText) {
                        onConfirm(port)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
