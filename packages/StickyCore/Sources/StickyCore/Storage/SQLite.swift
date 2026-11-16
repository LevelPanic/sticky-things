import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A deliberately tiny SQLite wrapper: one connection, prepared statements, transactions.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    /// `path == nil` opens an in-memory database (tests).
    init(path: String?) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path ?? ":memory:", &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw CoreError.database(message)
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit { sqlite3_close(handle) }

    var userVersion: Int {
        get { (try? query("PRAGMA user_version") { $0.int(0) }.first) ?? 0 }
        set { try? execute("PRAGMA user_version = \(newValue)") }
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw CoreError.database(message)
        }
    }

    func run(_ sql: String, _ bindings: [SQLValue] = []) throws {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw lastError() }
    }

    func query<T>(_ sql: String, _ bindings: [SQLValue] = [], map: (Row) throws -> T) throws -> [T] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(try map(Row(statement: statement)))
            } else if result == SQLITE_DONE {
                return rows
            } else {
                throw lastError()
            }
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ bindings: [SQLValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let s): sqlite3_bind_text(statement, index, s, -1, SQLITE_TRANSIENT)
            case .int(let i): sqlite3_bind_int64(statement, index, Int64(i))
            case .double(let d): sqlite3_bind_double(statement, index, d)
            case .blob(let data):
                _ = data.withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func lastError() -> CoreError {
        CoreError.database(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error")
    }

    struct Row {
        let statement: OpaquePointer?
        func text(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
        func blob(_ column: Int32) -> Data {
            guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        }
    }
}

enum SQLValue {
    case text(String), int(Int), double(Double), blob(Data), null
}
