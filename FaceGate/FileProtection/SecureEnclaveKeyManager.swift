import CryptoKit
import Foundation
import Security

final class SecureEnclaveKeyManager {
    static let shared = SecureEnclaveKeyManager()

    private let keychain = KeychainHelper.shared

    private var secureEnclaveAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        SecureEnclave.isAvailable
        #endif
    }

    private init() {}

    private func keyTag(for identifier: String) -> String {
        "com.dweep.FaceGate.fileKey.\(identifier)"
    }

    func generateFileKey(fileID: UUID) throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }

        if secureEnclaveAvailable {
            let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                .biometryCurrentSet,
                nil
            )
            guard let access = accessControl else {
                throw KeyError.accessControlFailed
            }

            let tag = keyTag(for: fileID.uuidString)
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: FGConstants.keychainService,
                kSecAttrAccount as String: tag,
                kSecValueData as String: keyData,
                kSecAttrAccessControl as String: access,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            ]

            SecItemDelete(addQuery as CFDictionary)
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeyError.keychainSaveFailed(status: status)
            }
        } else {
            let tag = keyTag(for: fileID.uuidString)
            try keychain.save(keyData, for: tag)
        }

        return key
    }

    func getFileKey(fileID: UUID) throws -> SymmetricKey {
        let tag = keyTag(for: fileID.uuidString)
        if secureEnclaveAvailable {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: FGConstants.keychainService,
                kSecAttrAccount as String: tag,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIAllow

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let keyData = result as? Data else {
                throw KeyError.keychainReadFailed(status: status)
            }
            return SymmetricKey(data: keyData)
        } else {
            guard let keyData = keychain.read(for: tag) else {
                throw KeyError.keyNotFound
            }
            return SymmetricKey(data: keyData)
        }
    }

    func deleteFileKey(fileID: UUID) {
        let tag = keyTag(for: fileID.uuidString)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: FGConstants.keychainService,
            kSecAttrAccount as String: tag,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func requiresAuthentication(for fileID: UUID) -> Bool {
        secureEnclaveAvailable
    }
}

enum KeyError: LocalizedError {
    case accessControlFailed
    case keychainSaveFailed(status: OSStatus)
    case keychainReadFailed(status: OSStatus)
    case keyNotFound
    case encryptionFailed
    case decryptionFailed
    case streamingFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessControlFailed:
            return "Failed to create access control for Secure Enclave"
        case .keychainSaveFailed(let status):
            return "Keychain save failed with status: \(status)"
        case .keychainReadFailed(let status):
            return "Keychain read failed with status: \(status)"
        case .keyNotFound:
            return "Encryption key not found"
        case .encryptionFailed:
            return "File encryption failed"
        case .decryptionFailed:
            return "File decryption failed"
        case .streamingFailed(let detail):
            return "Streaming error: \(detail)"
        }
    }
}
