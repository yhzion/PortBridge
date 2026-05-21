// PortBridge/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            Divider()
            ServerListView(vm: vm)
            errorStack
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 80, idealHeight: vm.serverSections.isEmpty ? 200 : 480)
        .frame(maxHeight: .infinity, alignment: .top)
        .task { await vm.scanAll() }
        .sheet(item: Binding(
            get: { vm.pendingPortConflict },
            set: { vm.pendingPortConflict = $0 }
        )) { conflict in
            PortConflictSheet(
                conflict: conflict,
                serverDisplayName: vm.serverDisplayName(for: conflict.serverId)
            ) { newPort in
                Task { await vm.resolveConflict(with: newPort) }
            }
        }
    }

    @ViewBuilder
    private var errorStack: some View {
        if !vm.errors.isEmpty {
            VStack(spacing: 4) {
                ForEach(vm.errors) { toast in
                    errorToast(toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.errors.map(\.id))
        }
    }

    private func errorToast(_ toast: ErrorToast) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.small)
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(toast.message)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("오류: \(toast.message)")
            Button {
                vm.dismissError(toast.id)
            } label: {
                Image(systemName: "xmark").imageScale(.small).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("에러 메시지 닫기")
            .accessibilityLabel("에러 메시지 닫기")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
        )
    }
}

struct PortConflictSheet: View {
    let conflict: PortConflict
    let serverDisplayName: String?
    let onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var localPortText: String

    init(conflict: PortConflict, serverDisplayName: String?, onConfirm: @escaping (Int) -> Void) {
        self.conflict = conflict
        self.serverDisplayName = serverDisplayName
        self.onConfirm = onConfirm
        _localPortText = State(initialValue: String(conflict.attemptedLocal + 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "로컬 포트 \(conflict.attemptedLocal)이(가) 사용 중입니다")
                .font(.headline)
            Text(verbatim: "다른 로컬 포트를 입력하세요. 리모트는 \(serverDisplayName ?? "서버"):\(conflict.remotePort).")
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
