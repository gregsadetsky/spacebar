import XCTest
import SQLite3
@testable import SpacebarKit

final class SQLiteInputTests: XCTestCase {
    /// builds a db file in a temp dir with the given sql
    func makeDB(_ tmp: TempDir, name: String = "t.sqlite3", sql: String) -> URL {
        let url = tmp.url.appendingPathComponent(name)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        XCTAssertEqual(rc, SQLITE_OK, err.map { String(cString: $0) } ?? "")
        sqlite3_close(db)
        return url
    }

    let fixture = """
    CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL, score REAL, photo BLOB, note TEXT DEFAULT 'none');
    INSERT INTO people VALUES (1, 'ann', 1.5, x'0102030405', NULL);
    INSERT INTO people VALUES (2, 'bob', NULL, NULL, 'hi');
    CREATE TABLE "weird ""name\"\"\" (x);
    INSERT INTO "weird ""name\"\"\" VALUES (42);
    CREATE INDEX people_name ON people(name);
    CREATE VIEW top AS SELECT name FROM people WHERE score > 1;
    PRAGMA user_version = 7;
    """

    func testSummaryShapes() throws {
        let tmp = TempDir()
        let url = makeDB(tmp, sql: fixture)
        let s = try SQLiteInput.summarize(url: url)
        XCTAssertEqual(s["userVersion"] as? Int, 7)
        XCTAssertEqual(s["encoding"] as? String, "UTF-8")
        XCTAssertEqual(s["pageSize"] as? Int, 4096)
        XCTAssertGreaterThan(s["fileSize"] as? Int ?? 0, 0)
        XCTAssertEqual(s["truncated"] as? Bool, false)

        let tables = s["tables"] as! [[String: Any]]
        XCTAssertEqual(tables.map { $0["name"] as? String }, ["people", "weird \"name\""])
        let people = tables[0]
        XCTAssertEqual(people["rowCount"] as? Int, 2)
        XCTAssertEqual(people["approx"] as? Bool, false)
        XCTAssertTrue((people["sql"] as? String ?? "").hasPrefix("CREATE TABLE people"))

        let columns = people["columns"] as! [[String: Any]]
        XCTAssertEqual(columns.map { $0["name"] as? String }, ["id", "name", "score", "photo", "note"])
        XCTAssertEqual(columns[0]["pk"] as? Bool, true)
        XCTAssertEqual(columns[1]["notnull"] as? Bool, true)
        XCTAssertEqual(columns[1]["pk"] as? Bool, false)
        XCTAssertEqual(columns[2]["type"] as? String, "REAL")
        XCTAssertEqual(columns[4]["default"] as? String, "'none'")

        let sample = people["sample"] as! [[Any]]
        XCTAssertEqual(sample.count, 2)
        XCTAssertEqual(sample[0][0] as? Int, 1)
        XCTAssertEqual(sample[0][1] as? String, "ann")
        XCTAssertEqual(sample[0][2] as? Double, 1.5)
        XCTAssertEqual((sample[0][3] as? [String: Int])?["blob"], 5, "blobs become {blob: length}")
        XCTAssertTrue(sample[0][4] is NSNull)
        XCTAssertTrue(sample[1][3] is NSNull)

        XCTAssertEqual((tables[1]["sample"] as? [[Any]])?.first?.first as? Int, 42, "quoted identifiers survive")

        let views = s["views"] as! [[String: Any]]
        XCTAssertEqual(views.map { $0["name"] as? String }, ["top"])
        let indexes = s["indexes"] as! [[String: Any]]
        XCTAssertEqual(indexes.map { $0["name"] as? String }, ["people_name"])
        XCTAssertEqual(indexes[0]["table"] as? String, "people")

        // the whole thing must be JSON-serializable for the bridge
        XCTAssertNoThrow(try Bridge.jsLiteral(s))
    }

    func testLoadViaInputLoader() throws {
        let tmp = TempDir()
        let url = makeDB(tmp, sql: fixture)
        guard case .sqlite(let s) = try InputLoader.load(kind: .sqlite, url: url, manifest: manifest("s", input: .sqlite)) else { return XCTFail() }
        XCTAssertEqual((s["tables"] as? [[String: Any]])?.count, 2)
    }

    func testSampleLimitAndCountBudget() throws {
        let tmp = TempDir()
        let url = makeDB(tmp, sql: """
        CREATE TABLE big (id INTEGER PRIMARY KEY, body TEXT);
        WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM s WHERE n < 5000)
        INSERT INTO big SELECT n, 'row ' || n FROM s;
        """)
        let s = try SQLiteInput.summarize(url: url)
        let big = (s["tables"] as! [[String: Any]])[0]
        XCTAssertEqual(big["rowCount"] as? Int, 5000)
        XCTAssertEqual((big["sample"] as? [[Any]])?.count, SQLiteInput.sampleRows)

        // a zero budget must interrupt the count: rowCount null, approx true
        let z = try SQLiteInput.summarize(url: url, countBudget: -1)
        let zbig = (z["tables"] as! [[String: Any]])[0]
        XCTAssertTrue(zbig["rowCount"] is NSNull, "\(String(describing: zbig["rowCount"]))")
        XCTAssertEqual(zbig["approx"] as? Bool, true)
        XCTAssertEqual((zbig["sample"] as? [[Any]])?.count, SQLiteInput.sampleRows, "samples still load after an interrupted count")
    }

    func testPayloadCapTruncates() throws {
        let tmp = TempDir()
        let url = makeDB(tmp, sql: """
        CREATE TABLE a (t TEXT); CREATE TABLE b (t TEXT);
        WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM s WHERE n < 50)
        INSERT INTO a SELECT substr(hex(randomblob(500)), 1, 1000) FROM s;
        INSERT INTO b SELECT t FROM a;
        """)
        let s = try SQLiteInput.summarize(url: url, payloadCap: 5000)
        XCTAssertEqual(s["truncated"] as? Bool, true)
        let tables = s["tables"] as! [[String: Any]]
        let aRows = (tables[0]["sample"] as! [[Any]]).count
        let bRows = (tables[1]["sample"] as! [[Any]]).count
        XCTAssertLessThan(aRows, 50)
        XCTAssertEqual(bRows, 0, "second table gets no samples once the cap is spent")
        XCTAssertEqual(tables[1]["rowCount"] as? Int, 50, "counts are still reported")
    }

    func testWALDatabaseWithoutSidecars() throws {
        let tmp = TempDir()
        let url = makeDB(tmp, sql: """
        PRAGMA journal_mode = WAL;
        CREATE TABLE w (x); INSERT INTO w VALUES (1), (2), (3);
        """)
        try? FileManager.default.removeItem(at: tmp.url.appendingPathComponent("t.sqlite3-wal"))
        try? FileManager.default.removeItem(at: tmp.url.appendingPathComponent("t.sqlite3-shm"))
        // header bytes 18/19 == 2 means wal mode
        let head = try Data(contentsOf: url)[18..<20]
        XCTAssertEqual([UInt8](head), [2, 2], "fixture is not in wal mode")
        let s = try SQLiteInput.summarize(url: url)
        XCTAssertEqual(((s["tables"] as! [[String: Any]])[0])["rowCount"] as? Int, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.url.appendingPathComponent("t.sqlite3-shm").path), "immutable open must not create sidecars")
    }

    func testNotADatabase() {
        let tmp = TempDir()
        XCTAssertThrowsError(try SQLiteInput.summarize(url: tmp.write("x.sqlite3", "just text, definitely not sqlite"))) { error in
            XCTAssertEqual(error as? InputError, .notSQLite)
        }
        XCTAssertThrowsError(try SQLiteInput.summarize(url: tmp.write("empty.sqlite3", ""))) { error in
            XCTAssertEqual(error as? InputError, .notSQLite)
        }
        XCTAssertThrowsError(try SQLiteInput.summarize(url: tmp.write("short.sqlite3", "SQLite format 3"))) { error in
            XCTAssertEqual(error as? InputError, .notSQLite, "15 of 16 magic bytes is not enough")
        }
    }

    func testMissingFile() {
        XCTAssertThrowsError(try SQLiteInput.summarize(url: URL(fileURLWithPath: "/nonexistent/x.sqlite3"))) { error in
            guard case .unreadable = error as? InputError else { return XCTFail("\(error)") }
        }
    }

    func testPathWithSpacesAndPercent() throws {
        let tmp = TempDir()
        let url = makeDB(tmp, name: "my db 100%.sqlite3", sql: "CREATE TABLE t (x); INSERT INTO t VALUES (1);")
        let s = try SQLiteInput.summarize(url: url)
        XCTAssertEqual(((s["tables"] as! [[String: Any]])[0])["rowCount"] as? Int, 1)
    }
}
