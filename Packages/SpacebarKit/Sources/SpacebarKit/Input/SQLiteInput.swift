import Foundation
import SQLite3

/// native sqlite summary for the `sqlite` input kind. opens the file with
/// `immutable=1` so wal databases work read-only inside the sandbox (no -wal
/// or -shm files get created next to the file).
public enum SQLiteInput: InputProvider {
    public static let sampleRows = 50
    /// per-table budget for SELECT COUNT(*); over it, rowCount is null + approx true
    public static let countBudget: TimeInterval = 0.2
    /// soft cap on the total size of sample values; samples are truncated past it
    public static let payloadCap = 2_000_000
    static let magic = Data("SQLite format 3\0".utf8)

    public static func load(url: URL, manifest: Manifest) throws -> InputPayload {
        .sqlite(try summarize(url: url))
    }

    public static func summarize(url: URL, countBudget: TimeInterval = SQLiteInput.countBudget, payloadCap: Int = SQLiteInput.payloadCap) throws -> [String: Any] {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { throw InputError.unreadable(url.path) }
        let head = try handle.read(upToCount: 16) ?? Data()
        try handle.close()
        guard head == magic else { throw InputError.notSQLite }

        let db = try Connection(url: url)
        var out: [String: Any] = [:]
        out["fileSize"] = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        out["pageSize"] = try db.scalarInt("PRAGMA page_size")
        out["encoding"] = try db.scalarText("PRAGMA encoding")
        out["userVersion"] = try db.scalarInt("PRAGMA user_version")

        var tables: [[String: Any]] = []
        var views: [[String: Any]] = []
        var indexes: [[String: Any]] = []
        var budgetLeft = payloadCap
        var truncated = false

        for row in try db.rows("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name") {
            let type = row[0] as? String ?? ""
            let name = row[1] as? String ?? ""
            let sql = row[3] as? String
            switch type {
            case "table":
                var t: [String: Any] = ["name": name, "type": "table", "sql": sql ?? NSNull()]
                t["columns"] = try db.rows("PRAGMA table_info(\(quote(name)))").map { c -> [String: Any] in
                    ["name": c[1] as? String ?? "", "type": c[2] as? String ?? "",
                     "notnull": (c[3] as? Int ?? 0) != 0, "pk": (c[5] as? Int ?? 0) != 0,
                     "default": c[4] ?? NSNull()]
                }
                let count = db.count(table: name, budget: countBudget)
                t["rowCount"] = count.map { $0 } ?? NSNull()
                t["approx"] = count == nil
                if budgetLeft > 0 {
                    let (sample, cost) = try db.sample(table: name, limit: sampleRows, budget: budgetLeft)
                    t["sample"] = sample
                    budgetLeft -= cost
                    if cost > budgetLeft + cost { truncated = true }
                } else {
                    t["sample"] = []
                    truncated = true
                }
                tables.append(t)
            case "view":
                views.append(["name": name, "sql": sql ?? NSNull()])
            case "index":
                indexes.append(["name": name, "table": row[2] as? String ?? "", "sql": sql ?? NSNull()])
            default:
                break
            }
        }
        out["tables"] = tables
        out["views"] = views
        out["indexes"] = indexes
        out["truncated"] = truncated
        return out
    }

    static func quote(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// thin wrapper over the C api; read-only, immutable, query_only
    final class Connection {
        private var db: OpaquePointer?

        init(url: URL) throws {
            var components = URLComponents()
            components.scheme = "file"
            components.path = url.path
            components.queryItems = [URLQueryItem(name: "immutable", value: "1"), URLQueryItem(name: "mode", value: "ro")]
            guard let uri = components.string else { throw InputError.sqlite("could not build uri") }
            let rc = sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
            guard rc == SQLITE_OK, let db else {
                let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed (\(rc))"
                sqlite3_close(db)
                throw InputError.sqlite(message)
            }
            sqlite3_exec(db, "PRAGMA query_only = 1", nil, nil, nil)
        }

        deinit { sqlite3_close(db) }

        var errorMessage: String { db.map { String(cString: sqlite3_errmsg($0)) } ?? "closed" }

        func rows(_ sql: String) throws -> [[Any]] {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw InputError.sqlite(errorMessage) }
            defer { sqlite3_finalize(stmt) }
            var result: [[Any]] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_ROW { result.append(Connection.values(stmt)) }
                else if rc == SQLITE_DONE { break }
                else { throw InputError.sqlite(errorMessage) }
            }
            return result
        }

        func scalarInt(_ sql: String) throws -> Int { (try rows(sql).first?.first as? Int) ?? 0 }
        func scalarText(_ sql: String) throws -> String { (try rows(sql).first?.first as? String) ?? "" }

        /// SELECT COUNT(*) with a time budget enforced through the progress
        /// handler; nil when interrupted
        func count(table: String, budget: TimeInterval) -> Int? {
            let deadline = Date().addingTimeInterval(budget)
            let box = Unmanaged.passRetained(DeadlineBox(deadline))
            defer { box.release() }
            sqlite3_progress_handler(db, 500, { ctx in
                let box = Unmanaged<DeadlineBox>.fromOpaque(ctx!).takeUnretainedValue()
                return Date() > box.deadline ? 1 : 0
            }, box.toOpaque())
            defer { sqlite3_progress_handler(db, 0, nil, nil) }
            return try? scalarInt("SELECT COUNT(*) FROM \(SQLiteInput.quote(table))")
        }

        /// first `limit` rows as json-friendly values; returns the rows and an
        /// estimate of their serialized size. stops early past `budget` bytes.
        func sample(table: String, limit: Int, budget: Int) throws -> ([[Any]], Int) {
            var cost = 0
            var out: [[Any]] = []
            for row in try rows("SELECT * FROM \(SQLiteInput.quote(table)) LIMIT \(limit)") {
                cost += row.reduce(8) { $0 + Connection.cost($1) }
                out.append(row)
                if cost > budget { break }
            }
            return (out, cost)
        }

        static func cost(_ v: Any) -> Int {
            switch v {
            case let s as String: return s.utf8.count + 3
            case is NSNull: return 5
            case let d as [String: Any]: return 12 + d.count * 8
            default: return 12
            }
        }

        static func values(_ stmt: OpaquePointer) -> [Any] {
            (0..<sqlite3_column_count(stmt)).map { i in
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: return Int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    let d = sqlite3_column_double(stmt, i)
                    return d.isFinite ? d : String(describing: d)
                case SQLITE_TEXT: return String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_BLOB: return ["blob": Int(sqlite3_column_bytes(stmt, i))]
                default: return NSNull()
                }
            }
        }
    }

    final class DeadlineBox {
        let deadline: Date
        init(_ d: Date) { deadline = d }
    }
}
