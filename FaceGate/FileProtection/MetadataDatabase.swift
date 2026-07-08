import Foundation
import SQLite3

final class MetadataDatabase {
    static let shared = MetadataDatabase()

    private var db: OpaquePointer?

    static var appGroupID: String {
        let teamID = "\(Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") ?? "")"
        return "\(teamID)com.dweep.FaceGate"
    }

    private var dbURL: URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            return container.appendingPathComponent("file_protection.db")
        }
        return FGConstants.appSupportDirectory.appendingPathComponent("file_protection.db")
    }

    private init() {
        openDatabase()
        createTable()
    }

    deinit {
        closeDatabase()
    }

    private func openDatabase() {
        let path = dbURL.path
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            print("[MetadataDB] Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
            db = nil
            return
        }
    }

    private func closeDatabase() {
        guard let db = db else { return }
        sqlite3_close(db)
        self.db = nil
    }

    private func createTable() {
        let query = """
        CREATE TABLE IF NOT EXISTS protected_files (
            id TEXT PRIMARY KEY,
            original_path TEXT NOT NULL,
            current_path TEXT NOT NULL,
            encrypted_key_tag TEXT NOT NULL,
            file_hash TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """
        exec(query)
    }

    @discardableResult
    private func exec(_ query: String) -> Bool {
        guard let db = db else { return false }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, query, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            if let err = errMsg {
                print("[MetadataDB] SQL error: \(String(cString: err))")
                sqlite3_free(err)
            }
            return false
        }
        return true
    }

    func insert(file: ProtectedFile) {
        let query = """
        INSERT OR REPLACE INTO protected_files (id, original_path, current_path, encrypted_key_tag, file_hash, mime_type, file_size, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let db = db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let idStr = file.id.uuidString
        let createdAt = ISO8601DateFormatter().string(from: file.createdAt)
        let updatedAt = ISO8601DateFormatter().string(from: file.updatedAt)

        sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (file.originalPath as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (file.currentPath as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (file.encryptedKeyTag as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (file.fileHash as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (file.mimeType as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 7, file.fileSize)
        sqlite3_bind_text(stmt, 8, (createdAt as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 9, (updatedAt as NSString).utf8String, -1, nil)

        sqlite3_step(stmt)
    }

    func delete(for id: UUID) {
        let query = "DELETE FROM protected_files WHERE id = ?;"
        guard let db = db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    func deleteByCurrentPath(_ path: String) {
        let query = "DELETE FROM protected_files WHERE current_path = ?;"
        guard let db = db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    func allFiles() -> [ProtectedFile] {
        var files: [ProtectedFile] = []
        let query = "SELECT * FROM protected_files;"
        guard let db = db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let originalPath = String(cString: sqlite3_column_text(stmt, 1))
            let currentPath = String(cString: sqlite3_column_text(stmt, 2))
            let keyTag = String(cString: sqlite3_column_text(stmt, 3))
            let fileHash = String(cString: sqlite3_column_text(stmt, 4))
            let mimeType = String(cString: sqlite3_column_text(stmt, 5))
            let fileSize = sqlite3_column_int64(stmt, 6)
            let createdAtStr = String(cString: sqlite3_column_text(stmt, 7))
            let updatedAtStr = String(cString: sqlite3_column_text(stmt, 8))

            guard let id = UUID(uuidString: idStr),
                  let createdAt = ISO8601DateFormatter().date(from: createdAtStr),
                  let updatedAt = ISO8601DateFormatter().date(from: updatedAtStr) else { continue }

            files.append(ProtectedFile(
                id: id,
                originalPath: originalPath,
                currentPath: currentPath,
                encryptedKeyTag: keyTag,
                fileHash: fileHash,
                mimeType: mimeType,
                fileSize: fileSize,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        return files
    }

    func file(forCurrentPath path: String) -> ProtectedFile? {
        let query = "SELECT * FROM protected_files WHERE current_path = ? LIMIT 1;"
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let originalPath = String(cString: sqlite3_column_text(stmt, 1))
            let currentPath = String(cString: sqlite3_column_text(stmt, 2))
            let keyTag = String(cString: sqlite3_column_text(stmt, 3))
            let fileHash = String(cString: sqlite3_column_text(stmt, 4))
            let mimeType = String(cString: sqlite3_column_text(stmt, 5))
            let fileSize = sqlite3_column_int64(stmt, 6)
            let createdAtStr = String(cString: sqlite3_column_text(stmt, 7))
            let updatedAtStr = String(cString: sqlite3_column_text(stmt, 8))

            guard let id = UUID(uuidString: idStr),
                  let createdAt = ISO8601DateFormatter().date(from: createdAtStr),
                  let updatedAt = ISO8601DateFormatter().date(from: updatedAtStr) else { return nil }

            return ProtectedFile(
                id: id,
                originalPath: originalPath,
                currentPath: currentPath,
                encryptedKeyTag: keyTag,
                fileHash: fileHash,
                mimeType: mimeType,
                fileSize: fileSize,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
        return nil
    }

    func fileCount() -> Int {
        let query = "SELECT COUNT(*) FROM protected_files;"
        guard let db = db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    func totalProtectedSize() -> Int64 {
        let query = "SELECT COALESCE(SUM(file_size), 0) FROM protected_files;"
        guard let db = db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return 0
    }

    func updateCurrentPath(for id: UUID, newPath: String) {
        let query = "UPDATE protected_files SET current_path = ?, updated_at = ? WHERE id = ?;"
        guard let db = db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (newPath as NSString).utf8String, -1, nil)
        let updatedAt = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 2, (updatedAt as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    func fileExists(withCurrentPath path: String) -> Bool {
        file(forCurrentPath: path) != nil
    }
}
