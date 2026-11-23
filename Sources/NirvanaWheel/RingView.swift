import SwiftUI

final class RingModel: ObservableObject {
    @Published var items: [RingItem] = []
    @Published var selected: Int?
    @Published var visible = false
    /// Title of the sub-menu being shown, nil at the top level.
    @Published var parentTitle: String?
    let geometry = WheelGeometry()
}

/// The ring itself. Drawn in a square of `RingView.size`, centred on the pointer.
struct RingView: View {
    static let size: CGFloat = 340
    @ObservedObject var model: RingModel

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.30) // #FFD84D

    var body: some View {
        let g = model.geometry
        let n = model.items.count
        ZStack {
            // Ring background
            AnnulusSector(inner: g.innerRadius, outer: g.outerRadius, start: 0, end: 2 * .pi)
                .fill(.ultraThinMaterial)
                .overlay(AnnulusSector(inner: g.innerRadius, outer: g.outerRadius, start: 0, end: 2 * .pi)
                    .fill(Color.black.opacity(0.45)))
                .overlay(AnnulusSector(inner: g.innerRadius, outer: g.outerRadius, start: 0, end: 2 * .pi)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1))

            if n > 0 {
                let slice = 2 * .pi / CGFloat(n)
                // Highlighted segment
                if let s = model.selected {
                    let mid = WheelGeometry.centreAngle(of: s, count: n)
                    AnnulusSector(inner: g.innerRadius + 3, outer: g.outerRadius - 3,
                                  start: mid - slice / 2 + 0.02, end: mid + slice / 2 - 0.02)
                        .fill(accent.opacity(0.9))
                        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: model.selected)
                }
                // Dividers
                ForEach(0..<n, id: \.self) { i in
                    let a = WheelGeometry.centreAngle(of: i, count: n) - slice / 2
                    Path { p in
                        p.move(to: point(a, g.innerRadius))
                        p.addLine(to: point(a, g.outerRadius))
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                // Icons
                ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                    let a = WheelGeometry.centreAngle(of: i, count: n)
                    let r = (g.innerRadius + g.outerRadius) / 2
                    let isSel = model.selected == i
                    Image(systemName: item.symbol)
                        .font(.system(size: isSel ? 24 : 20, weight: .semibold))
                        .foregroundStyle(isSel ? Color.black : Color.white.opacity(0.9))
                        .position(point(a, r))
                        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isSel)
                    if item.isMenu { // marks a sub-menu: push outwards to open it
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(isSel ? Color.black.opacity(0.7) : Color.white.opacity(0.5))
                            .rotationEffect(.radians(Double(a)))
                            .position(point(a, g.outerRadius - 12))
                    }
                }
            }

            // Centre: name of the highlighted item
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: g.innerRadius * 2 - 10, height: g.innerRadius * 2 - 10)
            let selTitle = model.selected.flatMap { $0 < n ? model.items[$0].title : nil }
            Text(selTitle ?? model.parentTitle.map { "‹ \($0)" } ?? "")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(selTitle == nil ? Color.white.opacity(0.55) : Color.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: g.innerRadius * 2 - 18)
        }
        .frame(width: Self.size, height: Self.size)
        .scaleEffect(model.visible ? 1 : 0.7)
        .opacity(model.visible ? 1 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: model.visible)
    }

    /// Point at clock angle `a` (0 = 12 o'clock, clockwise) and radius `r`, in this view's y-down space.
    private func point(_ a: CGFloat, _ r: CGFloat) -> CGPoint {
        let c = Self.size / 2
        return CGPoint(x: c + r * sin(a), y: c - r * cos(a))
    }
}

/// A ring segment between two clock angles. Built from sampled points, so the angle convention is explicit.
struct AnnulusSector: Shape {
    var inner: CGFloat
    var outer: CGFloat
    var start: CGFloat
    var end: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(start, end) }
        set { start = newValue.first; end = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        func pt(_ a: CGFloat, _ r: CGFloat) -> CGPoint { CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a)) }
        let steps = max(8, Int((end - start) / (2 * .pi) * 96))
        var p = Path()
        for k in 0...steps {
            let a = start + (end - start) * CGFloat(k) / CGFloat(steps)
            k == 0 ? p.move(to: pt(a, outer)) : p.addLine(to: pt(a, outer))
        }
        for k in stride(from: steps, through: 0, by: -1) {
            p.addLine(to: pt(start + (end - start) * CGFloat(k) / CGFloat(steps), inner))
        }
        p.closeSubpath()
        return p
    }
}
