import Foundation

struct ProtectedFile: Codable, Identifiable, Hashable {
    let id: UUID
    var originalPath: String
    var currentPath: String
    var encryptedKeyTag: String
    var fileHash: String
    var mimeType: String
    var fileSize: Int64
    var createdAt: Date
    var updatedAt: Date

    var originalURL: URL {
        URL(fileURLWithPath: originalPath)
    }

    var currentURL: URL {
        URL(fileURLWithPath: currentPath)
    }

    var displayName: String {
        originalURL.lastPathComponent
    }

    var displaySize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}
