import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - File Protection Settings Tab

struct FileProtectionSettingsView: View {
    @ObservedObject private var protectionManager = FileProtectionManager.shared
    @State private var showFilePicker = false
    @State private var showAuthDialog = false
    @State private var authReason = ""
    @State private var pendingAction: FileAction?
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var searchText = ""

    enum FileAction {
        case protect
        case unprotect(URL)
        case open(URL)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
                .overlay(Color.white.opacity(0.07))

            if protectionManager.protectedFiles.isEmpty {
                emptyStateView
            } else {
                fileListView
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Protected Files")
                    .font(.system(size: 15, weight: .bold))
                if !protectionManager.protectedFiles.isEmpty {
                    Text("\(protectionManager.protectedFilesCount) files  ·  \(ByteCountFormatter.string(fromByteCount: protectionManager.totalProtectedSize, countStyle: .file))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 160)

            Button(action: { showFilePicker = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Protect File…")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(protectionManager.isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    startProtect(url: url)
                }
            case .failure:
                break
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        Spacer()
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("No Protected Files")
                    .font(.system(size: 14, weight: .semibold))
                Text("Protect any file with face authentication.\nFiles stay in place — no vault needed.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 260)

            Button(action: { showFilePicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Protect File…")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        Spacer()
    }

    private var filteredFiles: [ProtectedFile] {
        let sorted = protectionManager.protectedFiles.sorted { $0.createdAt > $1.createdAt }
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var fileListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredFiles) { file in
                    ProtectedFileRow(file: file)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func startProtect(url: URL) {
        let securedURL = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        protectionManager.protectFile(at: url) { success, error in
            if !success, let error = error {
                alertMessage = error
                showAlert = true
            }
        }
    }
}

// MARK: - Protected File Row

private struct ProtectedFileRow: View {
    let file: ProtectedFile
    @ObservedObject private var protectionManager = FileProtectionManager.shared
    @State private var isHovered = false
    @State private var showConfirmRemove = false
    @State private var showConfirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                iconView

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(file.displaySize)
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(file.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 4) {
                Button(action: {
                    protectionManager.openProtectedFile(at: file.currentURL) { success, error in
                        if !success, let error = error {
                            // Show error to user
                        }
                    }
                }) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Open file")

                Button(action: { showConfirmRemove = true }) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Remove protection (decrypt)")
                .confirmationDialog(
                    "Unprotect \(file.displayName)?",
                    isPresented: $showConfirmRemove,
                    titleVisibility: .visible
                ) {
                    Button("Unprotect") {
                        protectionManager.unprotectFile(at: file.currentURL) { _, _ in }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The file will be decrypted back to its original location.")
                }

                Button(action: { showConfirmDelete = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Delete encrypted file")
                .confirmationDialog(
                    "Delete \(file.displayName)?",
                    isPresented: $showConfirmDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        deleteFile()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The encrypted file will be permanently deleted. This cannot be undone.")
                }
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var iconView: some View {
        let icon = NSWorkspace.shared.icon(forFile: file.originalPath)
        if icon.isValid {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
        } else {
            Image(systemName: "doc.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundColor(.secondary)
        }
    }

    private func deleteFile() {
        try? FileManager.default.removeItem(at: file.currentURL)
        MetadataDatabase.shared.delete(for: file.id)
        SecureEnclaveKeyManager.shared.deleteFileKey(fileID: file.id)
        FileProtectionManager.shared.refreshProtectedFiles()
    }
}

// MARK: - Action Auth Sheet

struct FileAuthView: View {
    let reason: String
    let onAuthenticated: () -> Void
    let onCancel: () -> Void

    @ObservedObject private var authManager = AuthenticationManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text(reason)
                .font(.system(size: 15, weight: .semibold))

            if authManager.authState == .authenticating(.faceUnlock) {
                ProgressView()
                    .controlSize(.large)
                Text("Looking for your face…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else if authManager.authState == .authenticating(.touchID) {
                ProgressView()
                    .controlSize(.large)
                Text("Touch ID…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Button("Cancel", role: .cancel) {
                onCancel()
            }
        }
        .padding()
        .frame(width: 280, height: 260)
    }
}
