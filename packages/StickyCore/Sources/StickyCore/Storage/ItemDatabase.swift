import Foundation

/// Durable storage for items. Each row keeps a few indexed columns plus the full item as JSON,
/// so the schema can grow without painful migrations. Writes are incremental and transactional.
final class ItemDatabase {
    static let schemaVersion = 1
    private let db: SQLiteDatabase
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    init(url: URL?) throws {
        db = try SQLiteDatabase(path: url?.path)
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("PRAGMA synchronous = NORMAL")
        try migrate()
    }

    private func migrate() throws {
        if db.userVersion < 1 {
            try db.transaction {
                try db.execute("""
                CREATE TABLE IF NOT EXISTS items (
                    id TEXT PRIMARY KEY,
                    created_at REAL NOT NULL,
                    pinned INTEGER NOT NULL DEFAULT 0,
                    kind TEXT NOT NULL,
                    body BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS items_created ON items(created_at DESC);
                CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                """)
            }
            db.userVersion = 1
        }
    }

    func loadAll() throws -> [Item] {
        var corrupt = 0
        let items = try db.query("SELECT body FROM items ORDER BY created_at DESC") { row -> Item? in
            do { return try decoder.decode(Item.self, from: row.blob(0)) } catch { corrupt += 1; return nil }
        }
        if corrupt > 0 { Log.store.error("Skipped \(corrupt) unreadable item rows") }
        return items.compactMap { $0 }
    }

    func upsert(_ item: Item) throws {
        try upsert([item])
    }

    func upsert(_ items: [Item]) throws {
        try db.transaction {
            for item in items {
                try db.run("""
                INSERT INTO items (id, created_at, pinned, kind, body) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET created_at = excluded.created_at, pinned = excluded.pinned,
                    kind = excluded.kind, body = excluded.body
                """, [.text(item.id.uuidString), .double(item.createdAt.timeIntervalSince1970),
                      .int(item.pinned ? 1 : 0), .text(item.kind.rawValue), .blob(try encoder.encode(item))])
            }
        }
    }

    func delete(_ ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try db.transaction {
            for id in ids { try db.run("DELETE FROM items WHERE id = ?", [.text(id.uuidString)]) }
        }
    }

    func meta(_ key: String) -> String? {
        (try? db.query("SELECT value FROM meta WHERE key = ?", [.text(key)]) { $0.text(0) })?.first
    }

    func setMeta(_ key: String, _ value: String) throws {
        try db.run("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                   [.text(key), .text(value)])
    }
}
