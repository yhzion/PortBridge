// PortBridge/Views/AddServerSheet.swift
import SwiftUI

struct AddServerSheet: View {
    let onSave: (Server) -> Void
    /// 입력된 `(user, host, port)` 3튜플이 이미 존재하는지 검사. 편집 시 자기 자신은 제외.
    /// nil이면 중복 검사 자체를 생략 (프리뷰/테스트 편의).
    let isDuplicate: ((_ user: String, _ host: String, _ port: Int) -> Bool)?
    var editing: Server?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var user: String = ""
    @State private var host: String = ""
    @State private var portText: String = "22"

    private var trimmedUser: String {
        user.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespaces)
    }

    private var isDuplicateInput: Bool {
        guard let isDuplicate, !trimmedUser.isEmpty, !trimmedHost.isEmpty, let port = parsedPort else {
            return false
        }
        return isDuplicate(trimmedUser, trimmedHost, port)
    }

    private var isValid: Bool {
        !trimmedUser.isEmpty
            && !trimmedHost.isEmpty
            && parsedPort != nil
            && !isDuplicateInput
    }

    /// 유효 SSH 포트: 1–65535. 0은 "임의 할당" 의미라 SSH 대상으로 부적합.
    private var parsedPort: Int? {
        guard let port = Int(portText.trimmingCharacters(in: .whitespaces)),
              (1 ... 65535).contains(port) else { return nil }
        return port
    }

    private var portValue: Int {
        parsedPort ?? 22
    }

    init(
        editing: Server? = nil,
        isDuplicate: ((_ user: String, _ host: String, _ port: Int) -> Bool)? = nil,
        onSave: @escaping (Server) -> Void
    ) {
        self.editing = editing
        self.isDuplicate = isDuplicate
        self.onSave = onSave
        if let server = editing {
            _name = State(initialValue: server.name ?? "")
            _user = State(initialValue: server.user)
            _host = State(initialValue: server.host)
            _portText = State(initialValue: "\(server.port)")
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
                if isDuplicateInput {
                    Text("이미 등록된 서버입니다 (\(trimmedUser)@\(trimmedHost):\(parsedPort ?? 22))")
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
