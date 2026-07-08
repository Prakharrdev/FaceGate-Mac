import Foundation

struct EncryptedFileHeader {
    let magic: UInt32
    let version: UInt8
    let nonce: Data
    let tag: Data
    let originalFilename: String
    let originalSize: Int64

    static let currentMagic: UInt32 = 0x46473031
    static let currentVersion: UInt8 = 1
    static let headerSize: Int = 1024

    var serialized: Data {
        var data = Data()
        withUnsafeBytes(of: magic.bigEndian) { data.append(contentsOf: $0) }
        data.append(version)
        let nonceLength = UInt8(nonce.count)
        data.append(nonceLength)
        data.append(nonce)
        let tagLength = UInt8(tag.count)
        data.append(tagLength)
        data.append(tag)
        withUnsafeBytes(of: originalSize.bigEndian) { data.append(contentsOf: $0) }
        let filenameData = originalFilename.data(using: .utf8) ?? Data()
        withUnsafeBytes(of: UInt16(filenameData.count).bigEndian) { data.append(contentsOf: $0) }
        data.append(filenameData)
        let remaining = EncryptedFileHeader.headerSize - data.count
        if remaining > 0 {
            data.append(Data(count: remaining))
        }
        return data
    }

    static func parse(from data: Data) -> EncryptedFileHeader? {
        guard data.count >= headerSize else { return nil }
        var offset = 0

        let magic = UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) })
        guard magic == currentMagic else { return nil }
        offset += MemoryLayout<UInt32>.size

        let version = data[offset]
        guard version == currentVersion else { return nil }
        offset += 1

        let nonceLength = data[offset]
        offset += 1
        guard offset + Int(nonceLength) <= data.count else { return nil }
        let nonce = data[offset..<offset + Int(nonceLength)]
        offset += Int(nonceLength)

        let tagLength = data[offset]
        offset += 1
        guard offset + Int(tagLength) <= data.count else { return nil }
        let tag = data[offset..<offset + Int(tagLength)]
        offset += Int(tagLength)

        let originalSize = data.withUnsafeBytes { buffer -> Int64 in
            let raw = buffer.baseAddress!.advanced(by: offset)
            return Int64(bigEndian: raw.load(as: Int64.self))
        }
        offset += MemoryLayout<Int64>.size

        guard offset + 2 <= data.count else { return nil }
        let filenameLength = data.withUnsafeBytes { buffer -> UInt16 in
            let raw = buffer.baseAddress!.advanced(by: offset)
            return UInt16(bigEndian: raw.load(as: UInt16.self))
        }
        offset += MemoryLayout<UInt16>.size

        guard offset + Int(filenameLength) <= data.count else { return nil }
        let filenameData = data[offset..<offset + Int(filenameLength)]
        guard let filename = String(data: filenameData, encoding: .utf8) else { return nil }

        return EncryptedFileHeader(
            magic: magic,
            version: version,
            nonce: nonce,
            tag: tag,
            originalFilename: filename,
            originalSize: originalSize
        )
    }
}

enum EncryptedFileFormat {
    static let fileExtension = "facegate"

    static func encryptedFileURL(for originalURL: URL) -> URL {
        originalURL.appendingPathExtension(fileExtension)
    }

    static func originalFileURL(from encryptedURL: URL) -> URL {
        let path = encryptedURL.path
        let ext = ".\(fileExtension)"
        guard path.hasSuffix(ext) else { return encryptedURL }
        let originalPath = String(path.dropLast(ext.count))
        return URL(fileURLWithPath: originalPath)
    }
}
