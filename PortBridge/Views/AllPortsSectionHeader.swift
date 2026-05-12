import SwiftUI

struct AllPortsSectionHeader: View {
    let count: Int

    var body: some View {
        Text(verbatim: "전체 포트 · \(count)")
    }
}
