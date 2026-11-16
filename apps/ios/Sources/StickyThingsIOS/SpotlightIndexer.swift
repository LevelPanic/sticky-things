import CoreSpotlight
import Foundation
import StickyCore
import UniformTypeIdentifiers

/// Puts saved items in the system Spotlight index. Everything stays on device, and concealed
/// password-manager copies are never indexed.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    private let index = CSSearchableIndex.default()
    private let domain = "items"

    static func identifier(for id: UUID) -> String { "item-\(id.uuidString)" }

    func reindex(_ items: [Item], store: ItemStore) {
        let searchable: [CSSearchableItem] = items
            .filter { !$0.concealed }
            .prefix(500)
            .map { item in
                let attributes = CSSearchableItemAttributeSet(contentType: contentType(for: item))
                attributes.title = item.headline
                let body = [item.caption, item.text, item.files.map(\.name).joined(separator: " ")]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                if !body.isEmpty { attributes.contentDescription = String(body.prefix(2000)) }
                attributes.keywords = [item.kind.label, item.source?.name].compactMap { $0 }
                return CSSearchableItem(uniqueIdentifier: Self.identifier(for: item.id),
                                        domainIdentifier: domain,
                                        attributeSet: attributes)
            }
        index.indexSearchableItems(searchable) { _ in }
    }

    func remove(_ id: UUID) {
        index.deleteSearchableItems(withIdentifiers: [Self.identifier(for: id)]) { _ in }
    }

    /// The item id from a Spotlight activity, or nil.
    static func itemID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let raw = UUID(uuidString: identifier.replacingOccurrences(of: "item-", with: "")) else {
            return nil
        }
        return raw
    }

    private func contentType(for item: Item) -> UTType {
        switch item.kind {
        case .text, .richText, .other, .color: return .text
        case .link: return .url
        case .image: return .image
        case .pdf: return .pdf
        case .file, .files: return .data
        case .folder: return .folder
        }
    }
}
