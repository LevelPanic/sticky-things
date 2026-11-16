import StickyIOSDesign
import SwiftUI

struct EmptyLibraryView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: StickySpace.xl) {
                StickyMiniNote()
                    .rotationEffect(.degrees(-5))
                    .padding(.top, StickySpace.xxl)
                VStack(spacing: StickySpace.s) {
                    Text("Nothing saved yet")
                        .font(StickyType.title)
                    Text("Write a note below, or save a link, photo or file. It stays on this iPhone, in the same library format as the Mac app.")
                        .font(StickyType.body)
                        .foregroundStyle(StickyPalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, StickySpace.l)

                VStack(alignment: .leading, spacing: StickySpace.m) {
                    tip("button.programmable", "Assign Sticky Things to the Action Button in Settings ▸ Action Button")
                    tip("switch.2", "Add the New Sticky Thing control to Control Center")
                    tip("square.and.arrow.up", "Or send anything here from another app with Share")
                    tip("hand.draw", "On iPad, drag items straight into the list")
                }
                .padding(StickySpace.l)
                .stickyCard()
                .padding(.horizontal, StickySpace.xl)
            }
            .padding(.bottom, StickySpace.xl)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: StickySpace.s) {
            Image(systemName: symbol)
                .frame(width: StickyMetrics.glyph)
                .foregroundStyle(StickyPalette.textSecondary)
            Text(text)
                .font(StickyType.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
