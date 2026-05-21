// PortBridge/Views/AddServerSheet.swift
import SwiftUI

struct AddServerSheet: View {
    let onSave: (Server) -> Void
    var editing: Server? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var user: String = ""
    @State private var host: String = ""
    @State private var portText: String = "22"

    private var isValid: Bool {
        !user.trimmingCharacters(in: .whitespaces).isEmpty
            && !host.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedPort != nil
    }

    /// 유효 SSH 포트: 1–65535. 0은 "임의 할당" 의미라 SSH 대상으로 부적합.
    private var parsedPort: Int? {
        guard let p = Int(portText.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(p) else { return nil }
        return p
    }

    private var portValue: Int { parsedPort ?? 22 }

    init(editing: Server? = nil, onSave: @escaping (Server) -> Void) {
        self.editing = editing
        self.onSave = onSave
        if let s = editing {
            _name = State(initialValue: s.name ?? "")
            _user = State(initialValue: s.user)
            _host = State(initialValue: s.host)
            _portText = State(initialValue: "\(s.port)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "서버 추가" : "서버 편집")
                .font(.headline)

            Form {
                TextField(text: $name, prompt: Text("선택사항")) { Text("이름") }
                TextField(text: $user, prompt: Text("user")) { Text("사용자") }
                    .disableAutocorrection(true)
                TextField(text: $host, prompt: Text("hostname 또는 IP")) { Text("호스트") }
                    .disableAutocorrection(true)
                TextField(text: $portText, prompt: Text("22")) { Text("포트") }
                if !portText.isEmpty && parsedPort == nil {
                    Text("1–65535 범위의 숫자여야 합니다")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "추가" : "저장") {
                    let server = Server(
                        id: editing?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name.trimmingCharacters(in: .whitespaces),
                        user: user.trimmingCharacters(in: .whitespaces),
                        host: host.trimmingCharacters(in: .whitespaces),
                        port: portValue
                    )
                    onSave(server)
                    dismiss()
                }
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
    }
}

#Preview("새 서버") {
    AddServerSheet(onSave: { _ in })
}

#Preview("서버 편집") {
    AddServerSheet(
        editing: Server(id: UUID(), name: "RTX 5090 Ubuntu", user: "yhzion", host: "100.74.124.72", port: 22),
        onSave: { _ in }
    )
}
