import StickyCore
import SwiftUI

/// A local thumbnail, loaded from the same blob store the Mac app uses.
struct ItemThumbnailView: View {
    let item: Item
    @ObservedObject var library: Library
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(IOSTheme.field)
                    .overlay {
                        Image(systemName: item.kind.iosSymbol)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: "\(item.id)-\(item.updatedAt.timeIntervalSince1970)") {
            image = await library.thumbnail(for: item)
        }
        .accessibilityHidden(true)
    }
}
