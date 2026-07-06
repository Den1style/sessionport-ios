import Foundation
import AuthenticationServices
import Security
import UIKit
import CryptoKit

// Google OAuth 2.0 via ASWebAuthenticationSession — no external SDK.
// Scope: drive.file (only files this app creates).
// Tokens: refresh_token stored in Keychain only. Access token in-memory only.

private let kClientID    = "747235685517-rrj7cgn3gchhte3sl61v35niibis0jbe.apps.googleusercontent.com"
private let kRedirectURI = "com.googleusercontent.apps.747235685517-rrj7cgn3gchhte3sl61v35niibis0jbe:/oauth2callback"
private let kScope       = "https://www.googleapis.com/auth/drive.file"
private let kFolderName  = "SessionPort Backups"
// Canonical two-way sync file — same name and folder as the extension
// (google-drive.js GDRIVE_SYNC_FILE), so both platforms converge on one file.
private let kSyncFileName = "sessionport-sync.json"
private let kKeychainSvc = "com.lusine.sessionport"
private let kKeychainAcc = "google_refresh_token"

// Max restore file size: 10 MB
private let kMaxRestoreBytes = 10 * 1024 * 1024

@MainActor
final class GoogleDriveService: ObservableObject {

    static let shared = GoogleDriveService()

    @Published var isConnected = false
    @Published var email: String? = nil
    @Published var lastSync: Date? = nil
    @Published var isSyncing = false
    @Published var syncError: String? = nil

    // In-memory only — never persisted to disk
    private var accessToken: String? = nil
    private var tokenExpiry: Date = .distantPast
    // Prevents two concurrent refreshes (race condition fix)
    private var refreshTask: Task<String, Error>? = nil
    // Retained for the lifetime of the auth session — `presentationContextProvider`
    // is weak, so a temporary would deallocate and the OAuth sheet wouldn't show.
    private var anchorProvider: WindowAnchorProvider? = nil

    private init() {
        email = SharedStorage.shared.driveEmail
        isConnected = email != nil
        lastSync = SharedStorage.shared.driveLastSync
    }

    // MARK: - Connect

    func connect() async throws {
        // PKCE: generate code_verifier + code_challenge (RFC 7636)
        let codeVerifier  = generateCodeVerifier()
        let codeChallenge = codeChallenge(from: codeVerifier)
        // State: CSRF protection (RFC 6749 §10.12)
        let state = UUID().uuidString

        let authURL = buildAuthURL(codeChallenge: codeChallenge, state: state)

        // @MainActor guarantees we're on the main thread — safe to read UIApplication
        guard let anchor = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        else { throw DriveError.noAuthCode }

        let code: String = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "com.googleusercontent.apps.747235685517-rrj7cgn3gchhte3sl61v35niibis0jbe"
            ) { url, error in
                if let error { cont.resume(throwing: error); return }
                guard let url,
                      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      let code = items.first(where: { $0.name == "code" })?.value,
                      !code.isEmpty
                else { cont.resume(throwing: DriveError.noAuthCode); return }
                // Verify state to prevent CSRF
                let returnedState = items.first(where: { $0.name == "state" })?.value
                guard returnedState == state else {
                    cont.resume(throwing: DriveError.stateMismatch); return
                }
                cont.resume(returning: code)
            }
            let provider = WindowAnchorProvider(window: anchor)
            anchorProvider = provider                       // strong ref keeps it alive
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        let tokens = try await exchangeCode(code, codeVerifier: codeVerifier)
        try saveRefreshToken(tokens.refreshToken)
        accessToken = tokens.accessToken
        tokenExpiry = Date().addingTimeInterval(Double(tokens.expiresIn) - 60)

        let profile = try await fetchProfile(token: tokens.accessToken)
        email = profile.email
        isConnected = true
        SharedStorage.shared.driveEmail = profile.email
    }

    // MARK: - Disconnect

    func disconnect() {
        deleteRefreshToken()
        // Wipe in-memory token immediately
        accessToken = nil
        tokenExpiry = .distantPast
        email = nil
        isConnected = false
        SharedStorage.shared.driveEmail = nil
        SharedStorage.shared.driveLastSync = nil
        lastSync = nil
    }

    // MARK: - Sync (two-way, canonical sessionport-sync.json — extension parity)
    //
    // Mirrors the extension's gdrive_syncNow (google-drive.js): pull the
    // canonical file, merge per-snapshot last-write-wins by state_at, push the
    // merged whole-DB export back to the same file. Both platforms on one
    // Google account converge to the same database; deletions propagate and
    // nothing resurrects (previously this method blindly restored the latest
    // backup file — one-way, no merge, resurrected trashed snapshots).

    func sync() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
        do {
            let token    = try await validToken()
            let folderID = try await ensureFolder(token: token)
            let fileID   = try await findSyncFile(token: token, folderID: folderID)

            // 1) Pull remote state and merge (LWW by state_at).
            if let id = fileID {
                let data = try await downloadFile(token: token, fileID: id)
                SharedStorage.shared.applySyncMerge(Snapshot.fromBackupJSON(data))
            } else {
                // No canonical file yet (extension < v1.0.5 or fresh account):
                // seed once from the newest classic backup so existing browser
                // data arrives, then create the canonical file below.
                let files = try await listFiles(token: token, folderID: folderID)
                if let latest = files.first {
                    let data = try await downloadFile(token: token, fileID: latest.id)
                    SharedStorage.shared.applySyncMerge(Snapshot.fromBackupJSON(data))
                }
            }

            // 2) Push the merged whole DB — including trashed snapshots with
            // deleted_at/state_at, so deletes reach the other device.
            let merged = SnapshotInterchange.exportJSON(
                SharedStorage.shared.snapshots, prettyPrinted: false)
            if let id = fileID {
                try await patchFile(token: token, fileID: id, data: merged)
            } else {
                try await uploadMultipart(named: kSyncFileName, token: token,
                                          folderID: folderID, data: merged)
            }

            SharedStorage.shared.driveLastSync = Date()
            lastSync = Date()
        } catch {
            syncError = error.localizedDescription
        }
    }

    // Auto-sync on app open, throttled to once per minute (extension parity:
    // popup-open autosync ≤ 1/min).
    func autoSyncIfNeeded() async {
        guard isConnected, !isSyncing else { return }
        if let last = SharedStorage.shared.driveLastSync,
           Date().timeIntervalSince(last) < 60 { return }
        await sync()
    }

    private func findSyncFile(token: String, folderID: String) async throws -> String? {
        let q = "name='\(kSyncFileName)' and '\(folderID)' in parents and trashed=false"
        struct FL: Decodable { let files: [DriveFile] }
        let r = try await authedGET(
            "https://www.googleapis.com/drive/v3/files?q=\(q.urlEncoded)&fields=files(id,name)&pageSize=1",
            token: token, as: FL.self
        )
        return r.files.first?.id
    }

    private func patchFile(token: String, fileID: String, data: Data) async throws {
        guard fileID.range(of: #"^[A-Za-z0-9_\-]{1,200}$"#, options: .regularExpression) != nil else {
            throw DriveError.invalidFileID
        }
        var req = URLRequest(url: URL(string:
            "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media&fields=id")!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw DriveError.uploadFailed }
    }

    // MARK: - Backup (upload current snapshots to Drive)

    func backup() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
        do {
            let token    = try await validToken()
            let folderID = try await ensureFolder(token: token)
            let data     = try makeBackupData()
            try await uploadBackup(token: token, folderID: folderID, data: data)
            SharedStorage.shared.driveLastSync = Date()
            lastSync = Date()
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func makeBackupData() throws -> Data {
        // Browser-compatible format (schema_version 1) — unified iOS ⇄ extension.
        // The same file restores in the Chrome extension and vice versa.
        let data = SnapshotInterchange.exportJSON(SharedStorage.shared.snapshots)
        guard !data.isEmpty else { throw DriveError.apiError }
        return data
    }

    private func uploadBackup(token: String, folderID: String, data: Data) async throws {
        let filename = "sessionport-backup-\(Int(Date().timeIntervalSince1970)).json"
        try await uploadMultipart(named: filename, token: token, folderID: folderID, data: data)
    }

    private func uploadMultipart(named filename: String, token: String, folderID: String, data: Data) async throws {
        let boundary  = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let metaJSON  = try JSONSerialization.data(withJSONObject: ["name": filename, "parents": [folderID]])

        var body = Data()
        func s(_ str: String) { body.append(Data(str.utf8)) }
        s("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metaJSON)
        s("\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n")
        body.append(data)
        s("\r\n--\(boundary)--")

        var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw DriveError.uploadFailed }
    }

    // MARK: - Token

    private func validToken() async throws -> String {
        if let t = accessToken, tokenExpiry > Date() { return t }
        // Coalesce concurrent refresh calls into one (race condition fix)
        if let ongoing = refreshTask { return try await ongoing.value }
        guard let refresh = loadRefreshToken() else { throw DriveError.notConnected }
        let task = Task<String, Error> {
            // Clear on success AND failure — a cached failed task would otherwise
            // replay the same error on every later sync until app restart.
            defer { self.refreshTask = nil }
            let r = try await self.refreshToken(refresh)
            self.accessToken = r.accessToken
            self.tokenExpiry = Date().addingTimeInterval(Double(r.expiresIn) - 60)
            return r.accessToken
        }
        refreshTask = task
        return try await task.value
    }

    // MARK: - PKCE helpers (RFC 7636)

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    private func codeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    // MARK: - OAuth

    private func buildAuthURL(codeChallenge: String, state: String) -> URL {
        // These are compile-time constants — force unwrap is safe
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id",             value: kClientID),
            .init(name: "redirect_uri",           value: kRedirectURI),
            .init(name: "response_type",          value: "code"),
            .init(name: "scope",                  value: kScope),
            .init(name: "access_type",            value: "offline"),
            .init(name: "prompt",                 value: "consent"),
            .init(name: "state",                  value: state),
            .init(name: "code_challenge",         value: codeChallenge),
            .init(name: "code_challenge_method",  value: "S256"),
        ]
        return c.url!
    }

    private struct Tokens: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private struct RefreshResult: Decodable {
        let accessToken: String
        let expiresIn: Int
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private func exchangeCode(_ code: String, codeVerifier: String) async throws -> Tokens {
        // Include code_verifier to complete PKCE flow
        let body = formBody([
            "code":          code,
            "client_id":     kClientID,
            "redirect_uri":  kRedirectURI,
            "grant_type":    "authorization_code",
            "code_verifier": codeVerifier,
        ])
        return try await postForm("https://oauth2.googleapis.com/token", body: body, as: Tokens.self)
    }

    private func refreshToken(_ rt: String) async throws -> RefreshResult {
        let body = formBody(["refresh_token": rt, "client_id": kClientID, "grant_type": "refresh_token"])
        return try await postForm("https://oauth2.googleapis.com/token", body: body, as: RefreshResult.self)
    }

    private struct Profile: Decodable { let email: String }

    private func fetchProfile(token: String) async throws -> Profile {
        try await authedGET("https://www.googleapis.com/oauth2/v2/userinfo", token: token, as: Profile.self)
    }

    // MARK: - Drive API

    private func ensureFolder(token: String) async throws -> String {
        let q = "name='\(kFolderName)' and mimeType='application/vnd.google-apps.folder' and trashed=false"
        struct Files: Decodable { let files: [[String: String]] }
        let r = try await authedGET(
            "https://www.googleapis.com/drive/v3/files?q=\(q.urlEncoded)&fields=files(id)&pageSize=1",
            token: token, as: Files.self
        )
        if let id = r.files.first?["id"] { return id }
        return try await createFolder(token: token)
    }

    private func createFolder(token: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode([
            "name": kFolderName,
            "mimeType": "application/vnd.google-apps.folder",
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw DriveError.folderCreationFailed }
        struct Created: Decodable { let id: String }
        return try JSONDecoder().decode(Created.self, from: data).id
    }

    private struct DriveFile: Decodable { let id: String; let name: String }

    private func listFiles(token: String, folderID: String) async throws -> [DriveFile] {
        let q = "'\(folderID)' in parents and trashed=false and mimeType='application/json'"
        struct FL: Decodable { let files: [DriveFile] }
        let r = try await authedGET(
            "https://www.googleapis.com/drive/v3/files?q=\(q.urlEncoded)&fields=files(id,name)&orderBy=createdTime+desc&pageSize=10",
            token: token, as: FL.self
        )
        return r.files
    }

    private func downloadFile(token: String, fileID: String) async throws -> Data {
        // Validate file ID — alphanumeric + dash/underscore only
        guard fileID.range(of: #"^[A-Za-z0-9_\-]{1,200}$"#, options: .regularExpression) != nil else {
            throw DriveError.invalidFileID
        }
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw DriveError.downloadFailed }
        guard data.count <= kMaxRestoreBytes else { throw DriveError.fileTooLarge }
        return data
    }

    // MARK: - HTTP helpers

    private func authedGET<T: Decodable>(_ urlStr: String, token: String, as: T.Type) async throws -> T {
        var req = URLRequest(url: URL(string: urlStr)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw DriveError.apiError }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postForm<T: Decodable>(_ urlStr: String, body: Data, as: T.Type) async throws -> T {
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw DriveError.authFailed }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func formBody(_ params: [String: String]) -> Data {
        params.map { k, v in "\(k)=\(v.urlEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }

    // MARK: - Keychain (refresh token only)

    private func saveRefreshToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else { throw DriveError.keychainFailed }
        let q: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        kKeychainSvc,
            kSecAttrAccount:        kKeychainAcc,
            kSecValueData:          data,
            kSecAttrAccessible:     kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(q as CFDictionary)
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw DriveError.keychainFailed }
    }

    private func loadRefreshToken() -> String? {
        let q: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  kKeychainSvc,
            kSecAttrAccount:  kKeychainAcc,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne,
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteRefreshToken() {
        let q: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: kKeychainSvc,
            kSecAttrAccount: kKeychainAcc,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Errors

enum DriveError: LocalizedError {
    case noAuthCode, notConnected, folderCreationFailed
    case invalidFileID, fileTooLarge, downloadFailed, uploadFailed, apiError, authFailed, keychainFailed
    case stateMismatch

    var errorDescription: String? {
        switch self {
        case .noAuthCode:           return "Authorization failed"
        case .stateMismatch:        return "Authorization state mismatch — possible CSRF attack"
        case .notConnected:         return "Not connected to Google Drive"
        case .folderCreationFailed: return "Failed to create backup folder"
        case .invalidFileID:        return "Invalid file ID"
        case .fileTooLarge:         return "Backup file exceeds 10 MB limit"
        case .downloadFailed:       return "Download failed"
        case .uploadFailed:         return "Upload failed"
        case .apiError:             return "Drive API error"
        case .authFailed:           return "Authentication failed"
        case .keychainFailed:       return "Failed to store credentials securely"
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

private final class WindowAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    init(window: UIWindow) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}

// MARK: - String extension

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
