import SwiftUI

/// A drawn Mac screen for the corner picker and the setup guide: a desktop tinted with your
/// accent color, the menu bar, a window and the Dock.
///
/// It's drawn rather than your wallpaper on purpose: reading the desktop picture can need
/// access to your Desktop, Documents or Downloads folder, and decoration never asks for a
/// permission. Corners stay clear for the corner spots and the peeking note.
public struct ScreenPreview: View {
    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            let bar = Palette.surfaceRaised.color.opacity(0.85)
            ZStack(alignment: .topLeading) {
                Palette.surfaceSunken.color
                Palette.accent.opacity(0.16)
                Rectangle()
                    .fill(bar)
                    .frame(width: w, height: h * 0.07)
                window(width: w * 0.46, height: h * 0.48)
                    .offset(x: w * 0.27, y: h * 0.2)
                Capsule()
                    .fill(bar)
                    .frame(width: w * 0.34, height: h * 0.08)
                    .offset(x: w * 0.33, y: h * 0.87)
            }
        }
        .accessibilityHidden(true)
    }

    private func window(width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        return VStack(spacing: 0) {
            Rectangle().fill(Palette.surfaceRaisedHover.color).frame(height: height * 0.16)
            Palette.surfaceRaised.color
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.border.color))
    }
}
