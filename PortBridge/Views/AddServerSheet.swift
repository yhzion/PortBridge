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

    private var isValid: Bool { !user.trimmingCharacters(in: .whitespaces).isEmpty && !host.trimmingCharacters(in: .whitespaces).isEmpty }
    private var portValue: Int { Int(portText) ?? 22 }

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
                TextField("표시 이름 (선택사항)", text: $name)
                TextField("사용자", text: $user)
                    .disableAutocorrection(true)
                TextField("호스트 (IP 또는 hostname)", text: $host)
                    .disableAutocorrection(true)
                TextField("포트", text: $portText)
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
