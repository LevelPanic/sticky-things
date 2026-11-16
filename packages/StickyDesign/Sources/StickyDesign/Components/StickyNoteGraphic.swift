import SwiftUI

public enum StickyPalette {
    public static let paperTop = Color(red: 1.00, green: 0.91, blue: 0.52)
    public static let paperBottom = Color(red: 1.00, green: 0.81, blue: 0.26)
    public static let flapTop = Color(red: 1.00, green: 0.97, blue: 0.80)
    public static let flapBottom = Color(red: 1.00, green: 0.88, blue: 0.48)
    public static let ink = Color(red: 0.45, green: 0.33, blue: 0.05)
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
public struct MiniStickyNote: View {
    public var size: CGFloat = 64
    /// Which corner of the note is folded.
    public var foldCorner: FoldCorner = .topLeft
    public var showLines = true

    public init(size: CGFloat = 64, foldCorner: FoldCorner = .topLeft, showLines: Bool = true) {
        self.size = size
        self.foldCorner = foldCorner
        self.showLines = showLines
    }

    public var body: some View {
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

/// Which corner of the note is folded over.
public enum FoldCorner: Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    public var isTop: Bool { self == .topLeft || self == .topRight }
}
