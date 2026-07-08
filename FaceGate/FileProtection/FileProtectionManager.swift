import AppKit
import Combine
import CryptoKit
import Foundation

final class FileProtectionManager: ObservableObject {
    static let shared = FileProtectionManager()

    @Published var protectedFiles: [ProtectedFile] = []
    @Published var isProcessing = false
    @Published var statusMessage: String?

    private let cryptoHelper = CryptoHelper.shared
    private let keyManager = SecureEnclaveKeyManager.shared
    private let metadataDB = MetadataDatabase.shared
    private let authManager = AuthenticationManager.shared

    private var tempFileMonitor: DispatchSourceFileSystemObject?
    private var tempFileURL: URL?
    private var launchedAppPID: pid_t?

    private let tempDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("com.dweep.FaceGate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        refreshProtectedFiles()
    }

    func refreshProtectedFiles() {
        protectedFiles = metadataDB.allFiles()
    }

    var protectedFilesCount: Int {
        metadataDB.fileCount()
    }

    var totalProtectedSize: Int64 {
        metadataDB.totalProtectedSize()
    }

    // MARK: - Protect File

    func protectFile(at url: URL, completion: @escaping (Bool, String?) -> Void) {
        guard !isProcessing else {
            completion(false, "Already processing another file")
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            completion(false, "File not found")
            return
        }

        guard url.pathExtension.lowercased() != EncryptedFileFormat.fileExtension else {
            completion(false, "File is already protected")
            return
        }

        let encryptedURL = EncryptedFileFormat.encryptedFileURL(for: url)
        guard !fileManager.fileExists(atPath: encryptedURL.path) else {
            completion(false, "Protected version already exists at \(encryptedURL.lastPathComponent)")
            return
        }

        isProcessing = true
        statusMessage = "Authenticating…"

        requestFileAuth(reason: "Protect \(url.lastPathComponent)") { [weak self] authenticated in
            guard let self = self else { return }
            guard authenticated else {
                self.isProcessing = false
                self.statusMessage = nil
                completion(false, "Authentication cancelled")
                return
            }

            DispatchQueue.global(qos: .userInitiated).async(execute: {
                do {
                    let fileID = UUID()
                    let fileData = try Data(contentsOf: url)
                    let fileHash = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
                    let key = try self.keyManager.generateFileKey(fileID: fileID)
                    let sealedBox = try AES.GCM.seal(fileData, using: key)
                    guard let combined = sealedBox.combined else {
                        throw KeyError.encryptionFailed
                    }

                    let nonceData = sealedBox.nonce.withUnsafeBytes { Data($0) }
                    let header = EncryptedFileHeader(
                        magic: EncryptedFileHeader.currentMagic,
                        version: EncryptedFileHeader.currentVersion,
                        nonce: nonceData,
                        tag: sealedBox.tag,
                        originalFilename: url.lastPathComponent,
                        originalSize: Int64(fileData.count)
                    )

                    var output = header.serialized
                    output.append(combined)

                    let tempEncryptedURL = self.tempDir.appendingPathComponent("\(fileID.uuidString).tmp")
                    try output.write(to: tempEncryptedURL, options: .atomic)

                    try fileManager.moveItem(at: tempEncryptedURL, to: encryptedURL)
                    try fileManager.removeItem(at: url)

                    let mimeType = self.mimeType(for: url)

                    let protectedFile = ProtectedFile(
                        id: fileID,
                        originalPath: url.path,
                        currentPath: encryptedURL.path,
                        encryptedKeyTag: fileID.uuidString,
                        fileHash: fileHash,
                        mimeType: mimeType,
                        fileSize: Int64(fileData.count),
                        createdAt: Date(),
                        updatedAt: Date()
                    )

                    self.metadataDB.insert(file: protectedFile)

                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.statusMessage = nil
                        self.refreshProtectedFiles()
                        completion(true, nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.statusMessage = nil
                        completion(false, error.localizedDescription)
                    }
                }
            })
        }
    }

    // MARK: - Unprotect File (decrypt in place)

    func unprotectFile(at url: URL, completion: @escaping (Bool, String?) -> Void) {
        guard !isProcessing else {
            completion(false, "Already processing another file")
            return
        }

        guard let protectedFile = metadataDB.file(forCurrentPath: url.path) else {
            completion(false, "File is not in the protection database")
            return
        }

        isProcessing = true
        statusMessage = "Authenticating…"

        requestFileAuth(reason: "Unprotect \(protectedFile.displayName)") { [weak self] authenticated in
            guard let self = self else { return }
            guard authenticated else {
                self.isProcessing = false
                self.statusMessage = nil
                completion(false, "Authentication cancelled")
                return
            }

            DispatchQueue.global(qos: .userInitiated).async(execute: {
                do {
                    let encryptedData = try Data(contentsOf: url)
                    let header = try self.parseHeader(from: encryptedData)
                    let key = try self.keyManager.getFileKey(fileID: protectedFile.id)
                    let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: header.nonce), ciphertext: encryptedData.subdata(in: EncryptedFileHeader.headerSize..<encryptedData.count), tag: header.tag)
                    let decrypted = try AES.GCM.open(sealedBox, using: key)

                    let originalURL = URL(fileURLWithPath: protectedFile.originalPath)
                    try decrypted.write(to: originalURL, options: .atomic)
                    try FileManager.default.removeItem(at: url)

                    self.metadataDB.delete(for: protectedFile.id)
                    self.keyManager.deleteFileKey(fileID: protectedFile.id)

                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.statusMessage = nil
                        self.refreshProtectedFiles()
                        completion(true, nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.statusMessage = nil
                        completion(false, error.localizedDescription)
                    }
                }
            })
        }
    }

    // MARK: - Open Protected File (decrypt to temp, launch app, monitor, cleanup)

    func openProtectedFile(at url: URL, completion: @escaping (Bool, String?) -> Void) {
        guard !isProcessing else {
            completion(false, "Already processing")
            return
        }

        guard let protectedFile = metadataDB.file(forCurrentPath: url.path) else {
            completion(false, "This file is not in the protection database")
            return
        }

        isProcessing = true
        statusMessage = "Authenticating…"

        requestFileAuth(reason: "Open \(protectedFile.displayName)") { [weak self] authenticated in
            guard let self = self else { return }
            guard authenticated else {
                self.isProcessing = false
                self.statusMessage = nil
                completion(false, "Authentication cancelled")
                return
            }

            DispatchQueue.global(qos: .userInitiated).async(execute: {
                do {
                    let encryptedData = try Data(contentsOf: url)
                    let header = try self.parseHeader(from: encryptedData)
                    let key = try self.keyManager.getFileKey(fileID: protectedFile.id)
                    let sealedBox = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: header.nonce), ciphertext: encryptedData.subdata(in: EncryptedFileHeader.headerSize..<encryptedData.count), tag: header.tag)
                    let decrypted = try AES.GCM.open(sealedBox, using: key)

                    let tempFileURL = self.tempDir.appendingPathComponent(header.originalFilename)
                    try decrypted.write(to: tempFileURL, options: .atomic)

                    DispatchQueue.main.async {
                        self.tempFileURL = tempFileURL
                        self.launchApp(toOpen: tempFileURL, originalURL: URL(fileURLWithPath: protectedFile.originalPath))
                        self.isProcessing = false
                        self.statusMessage = nil
                        completion(true, nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.statusMessage = nil
                        completion(false, error.localizedDescription)
                    }
                }
            })
        }
    }

    // MARK: - App Launch & Temp File Cleanup

    private func launchApp(toOpen tempURL: URL, originalURL: URL) {
        NSWorkspace.shared.open(tempURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.monitorTempFile(at: tempURL)
        }
    }

    private func monitorTempFile(at url: URL) {
        let fileManager = FileManager.default

        Thread.detachNewThread { [weak self] in
            guard let _ = self else { return }

            var waitCount = 0
            let maxWait: Int = 60

            while waitCount < maxWait {
                Thread.sleep(forTimeInterval: 1)
                waitCount += 1

                if !fileManager.fileExists(atPath: url.path) {
                    return
                }

                let tempPath = url.path
                let isOpen = NSWorkspace.shared.runningApplications.contains(where: { app in
                    app.isActive && app.ownsMenuBar
                })

                if !fileManager.fileExists(atPath: tempPath) {
                    return
                }
            }

            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Auth

    private func requestFileAuth(reason: String, completion: @escaping (Bool) -> Void) {
        let methods = authManager.availableAuthMethods()

        if methods.contains(.faceUnlock) {
            authManager.authenticateWithFace(completion: completion)
        } else if methods.contains(.touchID) {
            authManager.authenticateWithTouchID(appName: reason, completion: completion)
        } else if methods.contains(.appPassword) {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Authenticate to \(reason)"
                alert.informativeText = "Enter your FaceGate password."
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")

                let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                alert.accessoryView = passwordField
                alert.window.initialFirstResponder = passwordField

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    let success = self.authManager.authenticateWithPassword(passwordField.stringValue)
                    completion(success)
                } else {
                    completion(false)
                }
            }
        } else {
            completion(false)
        }
    }

    // MARK: - Helpers

    private func parseHeader(from data: Data) throws -> EncryptedFileHeader {
        guard let header = EncryptedFileHeader.parse(from: data) else {
            throw KeyError.decryptionFailed
        }
        return header
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "txt": return "text/plain"
        case "doc", "docx": return "application/msword"
        case "xls", "xlsx": return "application/vnd.ms-excel"
        case "ppt", "pptx": return "application/vnd.ms-powerpoint"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "zip": return "application/zip"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }

    // MARK: - File Monitoring (FSEvents)

    private var eventStream: FSEventStreamRef?

    func startFileMonitoring() {
        let paths = ["\(NSHomeDirectory())/Desktop",
                      "\(NSHomeDirectory())/Documents",
                      "\(NSHomeDirectory())/Downloads"] as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, numEvents, eventPaths, _, _ in
                let manager = Unmanaged<FileProtectionManager>.fromOpaque(info!).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
                var updates: Set<String> = []
                for i in 0..<Int(numEvents) {
                    if i < paths.count {
                        updates.insert(paths[i])
                    }
                }
                manager.handleFileSystemChanges(updatedPaths: updates)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        eventStream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stopFileMonitoring() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }

    private func handleFileSystemChanges(updatedPaths: Set<String>) {
        for path in updatedPaths {
            guard let existingFile = protectedFiles.first(where: { $0.currentPath == path }) else { continue }

            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

            if !exists || isDirectory.boolValue {
                metadataDB.delete(for: existingFile.id)
                keyManager.deleteFileKey(fileID: existingFile.id)
                refreshProtectedFiles()
            }
        }
    }
}
