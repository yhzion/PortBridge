// PortBridge/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            Divider()
            ServerListView(vm: vm)

            if let err = vm.lastError {
                errorBanner(err)
            }
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 80, idealHeight: vm.serverSections.isEmpty ? 200 : 480)
        .frame(maxHeight: .infinity, alignment: .top)
        .task { await vm.scanAll() }
        .sheet(item: Binding(
            get: { vm.pendingPortConflict },
            set: { vm.pendingPortConflict = $0 }
        )) { conflict in
            PortConflictSheet(conflict: conflict) { newPort in
                Task { await vm.resolveConflict(with: newPort) }
            }
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { vm.lastError = nil } label: {
                Image(systemName: "xmark").imageScale(.small).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("에러 메시지 닫기")
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
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
            Text(verbatim: "다른 로컬 포트를 입력하세요. 리모트는 \(conflict.serverDisplayName):\(conflict.remotePort).")
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
