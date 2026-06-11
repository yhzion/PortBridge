import AppKit
import SwiftUI

/// V2 변종: ∩ 아치 + ─ 베이스. ON 상태에서 아치 안에 점(트래픽 흐름).
/// badged면 우상단에 업데이트 표지 점 — 템플릿 이미지에 합성되어 CALayer 오버레이 없이
/// 다크/라이트·강조 색을 시스템이 처리한다.
/// 24×24 viewBox 좌표계로 그리고 frame 크기에 비례해 스케일됨.
struct MenuBarIconView: View {
    let active: Bool
    var badged: Bool = false
    var size: CGFloat = 18

    var body: some View {
        Canvas { ctx, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            let color = GraphicsContext.Shading.color(.black)
            let stroke = StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round)

            var arch = Path()
            arch.move(to: CGPoint(x: 5.5 * scale, y: 19 * scale))
            arch.addLine(to: CGPoint(x: 5.5 * scale, y: 12 * scale))
            arch.addQuadCurve(
                to: CGPoint(x: 12 * scale, y: 5.5 * scale),
                control: CGPoint(x: 5.5 * scale, y: 5.5 * scale)
            )
            arch.addQuadCurve(
                to: CGPoint(x: 18.5 * scale, y: 12 * scale),
                control: CGPoint(x: 18.5 * scale, y: 5.5 * scale)
            )
            arch.addLine(to: CGPoint(x: 18.5 * scale, y: 19 * scale))
            ctx.stroke(arch, with: color, style: stroke)

            var base = Path()
            base.move(to: CGPoint(x: 3 * scale, y: 19.6 * scale))
            base.addLine(to: CGPoint(x: 21 * scale, y: 19.6 * scale))
            ctx.stroke(base, with: color, style: stroke)

            if active {
                let radius: CGFloat = 3.4 * scale
                let dot = Path(ellipseIn: CGRect(
                    x: 12 * scale - radius,
                    y: 12.5 * scale - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                ctx.fill(dot, with: color)
            }

            if badged {
                let radius: CGFloat = 2.4 * scale
                let badge = Path(ellipseIn: CGRect(
                    x: 20 * scale - radius,
                    y: 4 * scale - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                ctx.fill(badge, with: color)
            }
        }
        .frame(width: size, height: size)
    }
}

/// SwiftUI 뷰를 메뉴바용 NSImage(Template)로 렌더.
/// Template 플래그를 켜면 macOS가 다크/라이트, 강조/비강조, 액세서리 모드의 색을 알아서 처리.
enum MenuBarIconRenderer {
    @MainActor
    static func image(active: Bool, badged: Bool = false, size: CGFloat = 18) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarIconView(active: active, badged: badged, size: size))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let fallback = NSImage(
            systemSymbolName: "arrow.triangle.swap",
            accessibilityDescription: "PortBridge"
        )
            ?? NSImage(size: NSSize(width: size, height: size))
        guard let nsImage = renderer.nsImage else {
            fallback.isTemplate = true
            return fallback
        }
        nsImage.isTemplate = true
        nsImage.accessibilityDescription = accessibilityDescription(active: active, badged: badged)
        return nsImage
    }

    /// 아이콘 상태(active × badged)의 보조기술 설명. 순수 함수로 분리해 테스트 대상으로 노출.
    static func accessibilityDescription(active: Bool, badged: Bool) -> String {
        let base = active
            ? String(localized: "menuBarIcon.a11y.active", defaultValue: "PortBridge — 포워딩 활성")
            : String(localized: "menuBarIcon.a11y.idle", defaultValue: "PortBridge — 대기 중")
        guard badged else { return base }
        return base + String(localized: "menuBarIcon.a11y.updateSuffix", defaultValue: ", 업데이트 있음")
    }
}

#Preview {
    HStack(spacing: 24) {
        VStack { MenuBarIconView(active: false); Text("OFF").font(.caption2) }
        VStack { MenuBarIconView(active: true); Text("ON").font(.caption2) }
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}
