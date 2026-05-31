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
            VStack(spacing: PBLayout.Space.s1) {
                ForEach(vm.errors) { toast in
                    errorToast(toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, PBLayout.Space.s1)
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
                .accessibilityLabel(String(localized: "content.errorToast.a11yLabel", defaultValue: "오류: \(toast.message)"))
            Button {
                vm.dismissError(toast.id)
            } label: {
                Image(systemName: "xmark").imageScale(.small).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "content.errorToast.dismiss", defaultValue: "에러 메시지 닫기"))
            .accessibilityLabel(String(localized: "content.errorToast.dismiss", defaultValue: "에러 메시지 닫기"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: PBLayout.Radius.sm, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PBLayout.Radius.sm, style: .continuous)
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

    /// 유효 로컬 포트: 1–65535이며 충돌난 포트와 달라야 함.
    private var parsedPort: Int? {
        guard let port = Int(localPortText.trimmingCharacters(in: .whitespaces)),
              (1 ... 65535).contains(port),
              port != conflict.attemptedLocal else { return nil }
        return port
    }

    private var validationMessage: String? {
        let trimmed = localPortText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let port = Int(trimmed), (1 ... 65535).contains(port) else {
            return String(localized: "content.conflict.invalidRange", defaultValue: "1–65535 범위의 숫자여야 합니다")
        }
        if port == conflict.attemptedLocal {
            return String(localized: "content.conflict.samePort", defaultValue: "이미 사용 중인 포트 \(conflict.attemptedLocal)와(과) 달라야 합니다")
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PBLayout.Space.s3) {
            Text(String(localized: "content.conflict.title", defaultValue: "로컬 포트 \(conflict.attemptedLocal)이(가) 사용 중입니다"))
                .font(.headline)
            Text(String(
                localized: "content.conflict.prompt",
                defaultValue: "다른 로컬 포트를 입력하세요. 리모트는 \(serverDisplayName ?? String(localized: "common.serverFallback", defaultValue: "서버")):\(conflict.remotePort)."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(String(localized: "content.conflict.localPortField", defaultValue: "로컬 포트"), text: $localPortText)
                .textFieldStyle(.roundedBorder)
            if let message = validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "common.cancel", defaultValue: "취소")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "content.conflict.connect", defaultValue: "연결")) {
                    if let port = parsedPort {
                        onConfirm(port)
                        dismiss()
                    }
                }
                .disabled(parsedPort == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
