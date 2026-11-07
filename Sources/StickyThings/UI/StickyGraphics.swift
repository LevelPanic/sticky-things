import SwiftUI

enum StickyPalette {
    static let paperTop = Color(red: 1.00, green: 0.91, blue: 0.52)
    static let paperBottom = Color(red: 1.00, green: 0.81, blue: 0.26)
    static let flapTop = Color(red: 1.00, green: 0.97, blue: 0.80)
    static let flapBottom = Color(red: 1.00, green: 0.88, blue: 0.48)
    static let ink = Color(red: 0.45, green: 0.33, blue: 0.05)
}

/// A sticky note whose top-leading corner is cut off diagonally (the dog-ear).
private struct DogEarBody: Shape {
    var fold: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = min(radius, w / 4, h / 4)
        var p = Path()
        p.move(to: CGPoint(x: fold, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - r))
        p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: r, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: fold))
        p.closeSubpath()
        return p
    }
}

/// The folded-over flap of the dog-ear.
private struct DogEarFlap: Shape {
    var fold: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: fold, y: 0))
        p.addLine(to: CGPoint(x: 0, y: fold))
        p.addQuadCurve(to: CGPoint(x: fold, y: fold), control: CGPoint(x: fold * 0.55, y: fold * 1.05))
        p.addQuadCurve(to: CGPoint(x: fold, y: 0), control: CGPoint(x: fold * 1.05, y: fold * 0.55))
        p.closeSubpath()
        return p
    }
}

/// A little yellow sticky note with a dog-eared corner — the app's visual signature.
struct MiniStickyNote: View {
    var size: CGFloat = 64
    /// Which corner of the note is folded.
    var foldCorner: ScreenCorner = .topLeft
    var showLines = true

    var body: some View {
        let fold = size * 0.26
        ZStack(alignment: .topLeading) {
            DogEarBody(fold: fold, radius: size * 0.08)
                .fill(LinearGradient(colors: [StickyPalette.paperTop, StickyPalette.paperBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if showLines {
                VStack(alignment: .leading, spacing: size * 0.09) {
                    Capsule().frame(width: size * 0.44, height: max(1.5, size * 0.045))
                    Capsule().frame(width: size * 0.56, height: max(1.5, size * 0.045))
                    Capsule().frame(width: size * 0.34, height: max(1.5, size * 0.045))
                }
                .foregroundStyle(StickyPalette.ink.opacity(0.28))
                .padding(.leading, size * 0.2)
                .padding(.top, size * 0.36)
            }
            DogEarFlap(fold: fold)
                .fill(LinearGradient(colors: [StickyPalette.flapTop, StickyPalette.flapBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.22), radius: size * 0.03, x: size * 0.015, y: size * 0.015)
        }
        .frame(width: size, height: size)
        .scaleEffect(x: foldCorner.isLeft ? 1 : -1, y: foldCorner.isTop ? 1 : -1)
    }
}

/// The opposite corner (used to fold the note's corner that faces the middle of the screen).
extension ScreenCorner {
    var opposite: ScreenCorner {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomLeft: return .topRight
        case .bottomRight: return .topLeft
        }
    }
}
