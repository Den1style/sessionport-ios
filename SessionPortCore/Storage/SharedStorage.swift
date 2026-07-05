import Foundation

private let kAppGroup     = "group.com.lusine.sessionport"
private let kSnapshots    = "sp_snapshots"
private let kPrompts      = "sp_prompts"
private let kFreeLimit    = 5
private let kMaxSnapshots = 200

// Flag stored separately so we know user intentionally cleared prompts
private let kPromptsSeeded = "sp_prompts_seeded"

@MainActor
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

    // Move to Trash (soft delete) — matches extension behaviour
    func moveToTrash(id: String) {
        var list = snapshots
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].deletedAt = Date()
        snapshots = list
    }

    func restoreFromTrash(id: String) {
        var list = snapshots
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].deletedAt = nil
        snapshots = list
    }

    func permanentlyDelete(id: String) {
        snapshots = snapshots.filter { $0.id != id }
    }

    func emptyTrash() {
        snapshots = snapshots.filter { !$0.isTrashed }
    }

    // Active (not trashed) snapshots — use everywhere except Trash screen
    var activeSnapshots: [Snapshot] { snapshots.filter { !$0.isTrashed } }
    var trashedSnapshots: [Snapshot] { snapshots.filter { $0.isTrashed } }

    // Projects — derived from active snapshots ("" would render as an invisible
    // chip and silently capture the selection, so filter it out)
    var allProjects: [String] {
        Array(Set(activeSnapshots.compactMap { $0.project }.filter { !$0.isEmpty })).sorted()
    }

    // One-shot fork target: when set (via Mind Map "+ Ветка"), the next keyboard
    // transfer branches from this snapshot instead of the project head. Cleared
    // after it is consumed.
    private var kKbForkParent: String { "sp_kb_fork_parent" }
    var kbForkParentId: String? {
        get { defaults.string(forKey: kKbForkParent) }
        set {
            if let v = newValue { defaults.set(v, forKey: kKbForkParent) }
            else { defaults.removeObject(forKey: kKbForkParent) }
        }
    }

    // Manually relink a snapshot's parent (Mind Map "🔗 Связь"). Rejects cycles.
    func setParent(of childId: String, to parentId: String) {
        guard childId != parentId else { return }
        var list = snapshots
        guard let childIdx = list.firstIndex(where: { $0.id == childId }) else { return }
        // Reject if parent is a descendant of child (would create a cycle).
        var cursor: String? = parentId
        var guardCount = 0
        while let c = cursor, guardCount < 10_000 {
            if c == childId { return }   // cycle → abort
            cursor = list.first(where: { $0.id == c })?.parentId
            guardCount += 1
        }
        list[childIdx].parentId = parentId
        snapshots = list
    }

    // Rename a project across all its snapshots (mirrors the browser's renameProject).
    func renameProject(_ old: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return }
        var list = snapshots
        for i in list.indices where list[i].project == old {
            list[i].project = trimmed
        }
        snapshots = list
        if kbProject == old { kbProject = trimmed }
    }

    // Kept for compatibility — returns active only
    func deleteSnapshot(id: String) { moveToTrash(id: id) }

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
        let code = (AppLanguage(rawValue: defaults.string(forKey: "sp_language") ?? "") ?? .system).code
        encode(PromptItem.demos(for: code), forKey: kPrompts)
        defaults.set(true, forKey: kPromptsSeeded)
    }

    // Active (not trashed) and trashed prompts
    var activePrompts: [PromptItem]  { prompts.filter { !$0.isTrashed } }
    var trashedPrompts: [PromptItem] { prompts.filter { $0.isTrashed } }

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

    // Soft delete → Trash
    func movePromptToTrash(id: String) {
        var list = prompts
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].deletedAt = Date()
        prompts = list
    }

    func restorePrompt(id: String) {
        var list = prompts
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].deletedAt = nil
        prompts = list
    }

    func permanentlyDeletePrompt(id: String) {
        prompts = prompts.filter { $0.id != id }
    }

    func emptyPromptsTrash() {
        prompts = prompts.filter { !$0.isTrashed }
    }

    // Kept for compatibility — now soft-deletes
    func deletePrompt(id: String) { movePromptToTrash(id: id) }

    // Merge imported prompts (dedup by id, newest on top).
    func importPrompts(_ items: [PromptItem]) {
        var list = prompts
        for item in items {
            list.removeAll { $0.id == item.id }
            list.insert(item, at: 0)
        }
        prompts = list
    }

    // MARK: - Keyboard UI state (persists across keyboard dismiss/recreate)
    //
    // The keyboard extension is torn down every time it is hidden, so its
    // SwiftUI @State is lost. Mirroring the browser extension, we persist the
    // in-progress transfer step here so the user resumes exactly where they left.

    private var kKbTab:      String { "sp_kb_tab" }        // "transfer" | "prompts"
    private var kKbFlowMode: String { "sp_kb_flow_mode" }  // "simple" | "extended" | absent
    private var kKbFlowStep: String { "sp_kb_flow_step" }  // Int

    var kbTab: String {
        get { defaults.string(forKey: kKbTab) ?? "transfer" }
        set { defaults.set(newValue, forKey: kKbTab) }
    }

    // nil → mode selection screen; non-nil → in-progress at the saved step
    var kbFlowMode: String? {
        get { defaults.string(forKey: kKbFlowMode) }
        set {
            if let v = newValue { defaults.set(v, forKey: kKbFlowMode) }
            else { defaults.removeObject(forKey: kKbFlowMode) }
        }
    }

    var kbFlowStep: Int {
        get { defaults.integer(forKey: kKbFlowStep) }
        set { defaults.set(newValue, forKey: kKbFlowStep) }
    }

    // Stable per-session transfer_id (mirrors the browser flow_state.transfer_id).
    // Generated when a transfer starts, reused in every prompt and as the saved
    // snapshot id, cleared when the transfer completes or is reset.
    private var kKbTransferId: String { "sp_kb_transfer_id" }
    var kbTransferId: String? {
        get { defaults.string(forKey: kKbTransferId) }
        set {
            if let v = newValue { defaults.set(v, forKey: kKbTransferId) }
            else { defaults.removeObject(forKey: kKbTransferId) }
        }
    }

    // Pasteboard changeCount recorded when the snapshot prompt is inserted.
    // The Save step lights up when the count moves on (user copied something
    // new) — metadata only, never triggers the system paste banner. -1 = unset.
    private var kKbClipCount: String { "sp_kb_clip_count" }
    var kbClipCountAtPrompt: Int {
        get { defaults.object(forKey: kKbClipCount) as? Int ?? -1 }
        set {
            if newValue < 0 { defaults.removeObject(forKey: kKbClipCount) }
            else { defaults.set(newValue, forKey: kKbClipCount) }
        }
    }

    // Selected target project for the next transfer (chosen in the keyboard).
    // Empty string → "new project" (LLM names it, starts a fresh chain).
    private var kKbProject: String { "sp_kb_project" }
    var kbProject: String {
        get { defaults.string(forKey: kKbProject) ?? "" }
        set { defaults.set(newValue, forKey: kKbProject) }
    }

    // Resolved interface language code ("en"/"ru") — usable from the extension.
    var kbLangCode: String {
        (AppLanguage(rawValue: defaults.string(forKey: "sp_language") ?? "") ?? .system).code
    }

    // MARK: - Pro

    var isPro: Bool {
        // UserDefaults is a cache only — StoreKitService is the source of truth
        get { defaults.bool(forKey: "sp_is_pro") }
        set { defaults.set(newValue, forKey: "sp_is_pro") }
    }

    var canAddSnapshot: Bool { isPro || activeSnapshots.count < kFreeLimit }
    var freeSnapshotsRemaining: Int { max(0, kFreeLimit - activeSnapshots.count) }

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
            // Structured log helps diagnose schema migrations; no secrets here.
            SessionLogger.storage.error("decode error for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
