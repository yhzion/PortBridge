import SwiftUI
import AppKit

/// V2 변종: ∩ 아치 + ─ 베이스. ON 상태에서 아치 안에 점(트래픽 흐름).
/// 24×24 viewBox 좌표계로 그리고 frame 크기에 비례해 스케일됨.
struct MenuBarIconView: View {
    let active: Bool
    var size: CGFloat = 18

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 24
            let color = GraphicsContext.Shading.color(.black)
            let stroke = StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round)

            var arch = Path()
            arch.move(to: CGPoint(x: 5.5 * s, y: 19 * s))
            arch.addLine(to: CGPoint(x: 5.5 * s, y: 12 * s))
            arch.addQuadCurve(
                to: CGPoint(x: 12 * s, y: 5.5 * s),
                control: CGPoint(x: 5.5 * s, y: 5.5 * s)
            )
            arch.addQuadCurve(
                to: CGPoint(x: 18.5 * s, y: 12 * s),
                control: CGPoint(x: 18.5 * s, y: 5.5 * s)
            )
            arch.addLine(to: CGPoint(x: 18.5 * s, y: 19 * s))
            ctx.stroke(arch, with: color, style: stroke)

            var base = Path()
            base.move(to: CGPoint(x: 3 * s, y: 19.6 * s))
            base.addLine(to: CGPoint(x: 21 * s, y: 19.6 * s))
            ctx.stroke(base, with: color, style: stroke)

            if active {
                let r: CGFloat = 2.2 * s
                let dot = Path(ellipseIn: CGRect(
                    x: 12 * s - r,
                    y: 12.5 * s - r,
                    width: r * 2,
                    height: r * 2
                ))
                ctx.fill(dot, with: color)
            }
        }
        .frame(width: size, height: size)
    }
}

/// SwiftUI 뷰를 메뉴바용 NSImage(Template)로 렌더.
/// Template 플래그를 켜면 macOS가 다크/라이트, 강조/비강조, 액세서리 모드의 색을 알아서 처리.
enum MenuBarIconRenderer {
    @MainActor
    static func image(active: Bool, size: CGFloat = 18) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarIconView(active: active, size: size))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let fallback = NSImage(systemSymbolName: "arrow.triangle.swap",
                               accessibilityDescription: "PortBridge")
            ?? NSImage(size: NSSize(width: size, height: size))
        guard let nsImage = renderer.nsImage else {
            fallback.isTemplate = true
            return fallback
        }
        nsImage.isTemplate = true
        nsImage.accessibilityDescription = active ? "PortBridge — Forwarding active"
                                                  : "PortBridge — Idle"
        return nsImage
    }
}

#Preview {
    HStack(spacing: 24) {
        VStack { MenuBarIconView(active: false); Text("OFF").font(.caption2) }
        VStack { MenuBarIconView(active: true);  Text("ON").font(.caption2)  }
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}
