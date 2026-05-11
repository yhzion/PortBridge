import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 12) {
            HostPickerView(vm: vm)
            Divider()
            if vm.hosts.isEmpty {
                ContentUnavailableView(
                    "~/.ssh/config 호스트 없음",
                    systemImage: "network.slash",
                    description: Text(vm.lastError ?? "SSH config을 확인하세요.")
                )
            } else {
                PortListView(vm: vm)
            }
            if let err = vm.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .frame(minWidth: 600, minHeight: 500)
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
            Text("로컬 포트 \(conflict.attemptedLocal)이(가) 사용 중입니다")
                .font(.headline)
            Text("다른 로컬 포트를 입력하세요. 리모트는 \(conflict.host):\(conflict.remotePort).")
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
