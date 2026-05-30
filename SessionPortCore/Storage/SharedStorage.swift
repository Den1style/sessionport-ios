import Foundation

private let kAppGroup     = "group.com.sessionport.app"
private let kSnapshots    = "sp_snapshots"
private let kPrompts      = "sp_prompts"
private let kFreeLimit    = 5
private let kMaxSnapshots = 200

// Flag stored separately so we know user intentionally cleared prompts
private let kPromptsSeeded = "sp_prompts_seeded"

final class SharedStorage {
    static let shared = SharedStorage()

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: kAppGroup) ?? .standard
        seedPromptsIfNeeded()
    }

    // MARK: - Snapshots

    var snapshots: [Snapshot] {
        get { decodeSafe([Snapshot].self, forKey: kSnapshots) ?? [] }
        set { encode(newValue, forKey: kSnapshots) }
    }

    func addSnapshot(_ snapshot: Snapshot) {
        var list = snapshots
        list.removeAll { $0.id == snapshot.id }
        list.insert(snapshot, at: 0)
        if list.count > kMaxSnapshots { list = Array(list.prefix(kMaxSnapshots)) }
        snapshots = list
    }

    func updateSnapshot(_ snapshot: Snapshot) {
        var list = snapshots
        guard let idx = list.firstIndex(where: { $0.id == snapshot.id }) else {
            addSnapshot(snapshot); return
        }
        list[idx] = snapshot
        snapshots = list
    }

    func deleteSnapshot(id: String) {
        snapshots = snapshots.filter { $0.id != id }
    }

    // Attach file to existing snapshot
    func attachFile(_ file: AttachedFile, toSnapshot id: String) {
        guard var snap = snapshots.first(where: { $0.id == id }) else { return }
        snap.attachedFiles.removeAll { $0.id == file.id }
        snap.attachedFiles.append(file)
        updateSnapshot(snap)
    }

    func removeFile(fileId: String, fromSnapshot snapId: String) {
        guard var snap = snapshots.first(where: { $0.id == snapId }) else { return }
        snap.attachedFiles.removeAll { $0.id == fileId }
        updateSnapshot(snap)
    }

    // MARK: - Prompts

    // Bug fix: demos only seed once on first launch. After that the list is user-owned.
    // If user deletes all prompts deliberately, list stays empty — no demos return.
    var prompts: [PromptItem] {
        get { decodeSafe([PromptItem].self, forKey: kPrompts) ?? [] }
        set { encode(newValue, forKey: kPrompts) }
    }

    private func seedPromptsIfNeeded() {
        guard !defaults.bool(forKey: kPromptsSeeded) else { return }
        encode(PromptItem.demos, forKey: kPrompts)
        defaults.set(true, forKey: kPromptsSeeded)
    }

    func addPrompt(_ prompt: PromptItem) {
        var list = prompts
        list.removeAll { $0.id == prompt.id }
        list.insert(prompt, at: 0)
        prompts = list
    }

    func updatePrompt(_ prompt: PromptItem) {
        var list = prompts
        guard let idx = list.firstIndex(where: { $0.id == prompt.id }) else {
            addPrompt(prompt); return
        }
        list[idx] = prompt
        prompts = list
    }

    func deletePrompt(id: String) {
        prompts = prompts.filter { $0.id != id }
    }

    // MARK: - Pro

    var isPro: Bool {
        // UserDefaults is a cache only — StoreKitService is the source of truth
        get { defaults.bool(forKey: "sp_is_pro") }
        set { defaults.set(newValue, forKey: "sp_is_pro") }
    }

    var canAddSnapshot: Bool { isPro || snapshots.count < kFreeLimit }
    var freeSnapshotsRemaining: Int { max(0, kFreeLimit - snapshots.count) }

    // MARK: - Drive state (email only, tokens in Keychain)

    var driveEmail: String? {
        get { defaults.string(forKey: "sp_drive_email") }
        set { defaults.set(newValue, forKey: "sp_drive_email") }
    }

    var driveLastSync: Date? {
        get {
            let t = defaults.double(forKey: "sp_drive_last_sync")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "sp_drive_last_sync") }
    }

    // MARK: - Helpers

    // decodeSafe logs failures instead of silently returning nil
    private func decodeSafe<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return try dec.decode(type, from: data)
        } catch {
            // Log to help diagnose schema migrations in future
            #if DEBUG
            print("[SharedStorage] decode error for \(key): \(error)")
            #endif
            return nil
        }
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
