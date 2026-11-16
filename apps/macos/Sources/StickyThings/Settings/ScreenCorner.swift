import AppKit
import StickyDesign
import SwiftUI

enum ScreenCorner: String, CaseIterable, Codable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }
    var isTop: Bool { self == .topLeft || self == .topRight }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }

    var name: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    /// Key fragment used by the Dock's hot corner preferences (wvous-br-corner …).
    var dockKey: String {
        switch self {
        case .topLeft: return "tl"
        case .topRight: return "tr"
        case .bottomLeft: return "bl"
        case .bottomRight: return "br"
        }
    }

    /// SwiftUI anchor (y grows downward in SwiftUI).
    var unitPoint: UnitPoint {
        switch self {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    /// The corner point of `rect` in AppKit coordinates (origin bottom-left).
    func point(in rect: NSRect) -> NSPoint {
        NSPoint(x: isLeft ? rect.minX : rect.maxX, y: isTop ? rect.maxY : rect.minY)
    }

    /// A rect of `size` tucked into this corner of `rect`, `inset` points away from the edges.
    func rect(size: NSSize, in rect: NSRect, inset: CGFloat = 0) -> NSRect {
        let x = isLeft ? rect.minX + inset : rect.maxX - size.width - inset
        let y = isTop ? rect.maxY - size.height - inset : rect.minY + inset
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// A corner is "hard" when the pointer cannot slide past it onto another display,
    /// which is what makes a hot corner easy to hit and hard to trigger by accident.
    static func isHard(_ corner: ScreenCorner, of frame: NSRect, among frames: [NSRect]) -> Bool {
        let p = corner.point(in: frame)
        let inside = NSPoint(x: corner.isLeft ? p.x + 0.5 : p.x - 0.5,
                             y: corner.isTop ? p.y - 0.5 : p.y + 0.5)
        let dx: CGFloat = corner.isLeft ? -1 : 1
        let dy: CGFloat = corner.isTop ? 1 : -1
        let probes = [NSPoint(x: inside.x + dx, y: inside.y), NSPoint(x: inside.x, y: inside.y + dy)]
        for other in frames where other != frame {
            if probes.contains(where: { other.contains($0) }) { return false }
        }
        return true
    }
}

extension ScreenCorner {
    var opposite: ScreenCorner {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomLeft: return .topRight
        case .bottomRight: return .topLeft
        }
    }

    /// The note peeking out of this corner folds the corner that faces the middle of the screen.
    var peekFold: FoldCorner {
        switch opposite {
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        }
    }
}

enum CornerTrigger: String, CaseIterable, Codable, Identifiable {
    case click, hover
    var id: String { rawValue }
    var name: String { self == .click ? "Click" : "Hover" }
}

/// How far from the corner a drag is caught while the mouse button is down. The corner is tiny
/// at rest (so it never gets in the way); this is the temporary catcher that makes drags easy.
enum CornerDragArea: String, CaseIterable, Codable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var name: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    /// The side of the square catch area, in points.
    var size: CGFloat {
        switch self {
        case .small: return 44
        case .medium: return 72
        case .large: return 120
        }
    }
}
