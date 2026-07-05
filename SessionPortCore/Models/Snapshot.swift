import Foundation

private let kMaxShortStr = 500
private let kMaxLongStr  = 5_000
private let kMaxArrayLen = 100

// File attached to a snapshot — stored as base64 in App Group UserDefaults
struct AttachedFile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var mimeType: String
    var sizeBytes: Int
    var base64: String      // actual content, max 5 MB

    var displaySize: String {
        let kb = Double(sizeBytes) / 1024
        return kb < 1024 ? String(format: "%.1f KB", kb) : String(format: "%.1f MB", kb / 1024)
    }

    // Truncated text preview for insertion into LLM
    func textContent() -> String? {
        guard let data = Data(base64Encoded: base64),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return String(text.prefix(50_000))
    }
}

struct Snapshot: Codable, Identifiable, Hashable {
    var id: String
    var parentId: String?
    var title: String
    var goal: String
    var decisions: [String]
    var rejected: [String]
    var state: String
    var nextStep: String
    var llmSource: String
    var project: String?       // project name, mirrors extension
    var createdAt: Date
    var deletedAt: Date?       // non-nil → in Trash
    var attachedFiles: [AttachedFile]

    var isTrashed: Bool { deletedAt != nil }

    init(
        id: String = UUID().uuidString,
        parentId: String? = nil,
        title: String,
        goal: String = "",
        decisions: [String] = [],
        rejected: [String] = [],
        state: String = "",
        nextStep: String = "",
        llmSource: String = "",
        project: String? = nil,
        createdAt: Date = Date(),
        deletedAt: Date? = nil,
        attachedFiles: [AttachedFile] = []
    ) {
        self.id = id; self.parentId = parentId; self.title = title
        self.goal = goal; self.decisions = decisions; self.rejected = rejected
        self.state = state; self.nextStep = nextStep; self.llmSource = llmSource
        self.project = project; self.createdAt = createdAt
        self.deletedAt = deletedAt; self.attachedFiles = attachedFiles
    }

    enum CodingKeys: String, CodingKey {
        case id = "transfer_id"; case parentId = "parent_transfer_id"
        case title, goal, decisions, rejected, state, project
        case nextStep = "next_step"; case llmSource = "llm_source"
        case createdAt = "created_at"; case deletedAt = "deleted_at"
        case attachedFiles = "attached_files"
    }

    // Full context text including file contents
    func contextText(includeFiles: Bool = true) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601

        // Encode without files for the JSON block
        var copy = self; copy.attachedFiles = []
        guard let data = try? enc.encode(copy),
              let json = String(data: data, encoding: .utf8) else {
            return "---BEGIN CONTEXT---\n\(title)\n---END CONTEXT---"
        }

        var result = "---BEGIN CONTEXT---\n\(json)\n---END CONTEXT---"

        if includeFiles {
            for file in attachedFiles {
                if let text = file.textContent() {
                    result += "\n\n---FILE: \(file.name)---\n\(text)\n---END FILE---"
                }
            }
        }
        return result
    }

    // Restoration prompt: prepends layered instructions to the raw context payload,
    // mirroring the browser extension's restore flow. Fields referenced match the
    // flat snapshot schema actually stored on iOS (goal / decisions / rejected /
    // state / next_step) — NOT the extension's nested v1.1 keys, which iOS discards
    // on ingestion. Bilingual via kbLangCode.
    @MainActor
    func restoreContext(includeFiles: Bool = true) -> String {
        let isEn = SharedStorage.shared.kbLangCode == "en"
        let preamble = isEn ? """
        SessionPort PROTOCOL — CONTEXT RESTORATION.

        Read the snapshot and restore the working context:
        1. goal — accept as the project's identity and continuation instruction
        2. decisions — settled choices; treat as already agreed
        3. rejected — never suggest these again, no matter how reasonable they look
        4. state — where we are; next_step is your first action
        Then continue the work from next_step.
        """ : """
        ПРОТОКОЛ SessionPort — ВОССТАНОВЛЕНИЕ КОНТЕКСТА.

        Прочитай слепок и восстанови рабочий контекст:
        1. goal — прими как идентичность проекта и инструкцию-продолжение
        2. decisions — принятые решения; считай уже согласованными
        3. rejected — никогда не предлагай это повторно, каким бы разумным оно ни казалось
        4. state — где мы; next_step — твоё первое действие
        Затем продолжи работу с next_step.
        """
        return preamble + "\n\n" + contextText(includeFiles: includeFiles)
    }
}

// MARK: - Parsing

extension Snapshot {
    // Parses backup JSON. Handles schema_version 1 (browser ext format) and
    // schema_version 2 (iOS Codable format produced by ExportView).
    static func fromBackupJSON(_ data: Data) -> [Snapshot] {
        guard data.count <= 10 * 1024 * 1024,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapsRaw = obj["snapshots"] else { return [] }

        let version = obj["schema_version"] as? Int ?? 1

        if version >= 2, let arr = snapsRaw as? [[String: Any]],
           let arrData = try? JSONSerialization.data(withJSONObject: arr) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let decoded = try? dec.decode([Snapshot].self, from: arrData) {
                return Array(decoded.prefix(500))
            }
        }

        guard let snaps = snapsRaw as? [[String: Any]] else { return [] }
        return snaps.prefix(500).compactMap { fromRawDict($0) }
    }

    // Parses LLM output JSON (iOS SessionPort schema v1.1 with meta/dna/decisions/state).
    static func fromLLMOutput(_ text: String, llmSource: String = "") -> Snapshot? {
        let jsonStr = extractJSONString(from: text)
        var parsed = decodeObject(jsonStr)
        if parsed == nil {
            // Chat UIs render the model's straight quotes as smart “curly” ones;
            // text copied by selection then fails strict JSON parsing. Normalize
            // and retry before giving up.
            parsed = decodeObject(normalizeSmartQuotes(jsonStr))
        }
        guard let obj = parsed else { return nil }

        let meta  = obj["meta"]  as? [String: Any]
        let dna   = obj["dna"]   as? [String: Any]
        let st    = obj["state"] as? [String: Any]
        let decisionsArr = obj["decisions"] as? [[String: Any]] ?? []

        guard let id = (meta?["transfer_id"] as? String)?.truncated(kMaxShortStr), !id.isEmpty else { return nil }

        // Partition with no data loss: only explicit "rejected" goes to rejected;
        // everything else (accepted, rule, missing/unknown type) → accepted.
        func describe(_ d: [String: Any]) -> String? {
            guard let what = (d["what"] as? String)?.truncated(kMaxShortStr), !what.isEmpty else { return nil }
            if let why = (d["why"] as? String), !why.isEmpty { return "\(what) — \(why)" }
            return what
        }
        let accepted = decisionsArr
            .filter { ($0["type"] as? String) != "rejected" }
            .compactMap(describe)
        let rejected = decisionsArr
            .filter { ($0["type"] as? String) == "rejected" }
            .compactMap(describe)

        let goal        = (dna?["goal"]         as? String)?.truncated(kMaxLongStr)  ?? ""
        let currentTask = (st?["current_task"]  as? String)?.truncated(kMaxShortStr) ?? ""
        let nextStep    = (st?["next_step"]      as? String)?.truncated(kMaxLongStr)  ?? ""
        let lastActions = (st?["last_actions"]   as? [String]) ?? []
        let stateStr    = ([currentTask] + lastActions.prefix(3))
            .filter { !$0.isEmpty }.joined(separator: " · ").truncated(kMaxShortStr)

        let project = (meta?["project"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let title: String
        if !goal.isEmpty { title = String(goal.prefix(80)) }
        else if let p = project { title = "[\(p)] Context" }
        else { title = "Context" }

        var createdAt = Date()
        if let dateStr = meta?["date"] as? String {
            createdAt = parseDateOnly(dateStr) ?? Date()
        }

        return Snapshot(
            id: id,
            title: title,
            goal: goal,
            decisions: Array(accepted.prefix(kMaxArrayLen)),
            rejected: Array(rejected.prefix(kMaxArrayLen)),
            state: stateStr,
            nextStep: nextStep,
            llmSource: llmSource,
            project: project,
            createdAt: createdAt
        )
    }

    private static func decodeObject(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // “ ” „ → "  and  ‘ ’ → '  (only used as a retry after strict parsing fails,
    // so valid JSON with intentional curly quotes inside values is never touched)
    static func normalizeSmartQuotes(_ s: String) -> String {
        var t = s
        for q in ["\u{201C}", "\u{201D}", "\u{201E}"] {
            t = t.replacingOccurrences(of: q, with: "\"")
        }
        for q in ["\u{2018}", "\u{2019}"] {
            t = t.replacingOccurrences(of: q, with: "'")
        }
        return t
    }

    // Extracts JSON string from LLM response text (handles markdown blocks and SP markers).
    static func extractJSONString(from text: String) -> String {
        if let r1 = text.range(of: "---BEGIN CONTEXT---"),
           let r2 = text.range(of: "---END CONTEXT---", range: r1.upperBound..<text.endIndex) {
            return String(text[r1.upperBound..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let r1 = text.range(of: "```json"),
           let r2 = text.range(of: "```", range: r1.upperBound..<text.endIndex) {
            return String(text[r1.upperBound..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let r1 = text.range(of: "```"),
           let r2 = text.range(of: "```", range: r1.upperBound..<text.endIndex) {
            let candidate = String(text[r1.upperBound..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.hasPrefix("{") { return candidate }
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }

    static func fromRawDict(_ d: [String: Any]) -> Snapshot? {
        // Browser records nest the anchors under `payload`; older/flat formats
        // keep them at the top level. Support both.
        let payload = d["payload"] as? [String: Any]
        let meta    = (payload?["meta"]    as? [String: Any]) ?? (d["meta"]    as? [String: Any])
        let core    = (payload?["core"]    as? [String: Any]) ?? (d["core"]    as? [String: Any])
        let ledger  = (payload?["ledger"]  as? [String: Any]) ?? (d["ledger"]  as? [String: Any])
        let runtime = (payload?["runtime"] as? [String: Any]) ?? (d["runtime"] as? [String: Any])

        // id: prefer transfer_id (top or meta), fall back to snapshot_id
        let rawId = (d["transfer_id"] as? String)
            ?? (meta?["transfer_id"] as? String)
            ?? (d["snapshot_id"] as? String)
        guard let id = rawId?.truncated(kMaxShortStr), !id.isEmpty else { return nil }

        let goal    = (core?["intent"] as? String)?.truncated(kMaxLongStr) ?? ""
        let project = (meta?["project"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        // Title: explicit title if present, else derive from goal/project.
        let title: String
        if let t = (d["title"] as? String)?.truncated(kMaxShortStr), !t.isEmpty {
            title = t
        } else if !goal.isEmpty {
            title = String(goal.prefix(80))
        } else if let p = project {
            title = "[\(p)] Context"
        } else {
            title = "Context"
        }

        let llmRaw = (d["source_host"] as? String)
            ?? (d["llm_source"] as? String)
            ?? (meta?["llm_source"] as? String)

        return Snapshot(
            id:        id,
            parentId:  (d["parent_transfer_id"] as? String)?.truncated(kMaxShortStr)
                        ?? (meta?["parent_transfer_id"] as? String)?.truncated(kMaxShortStr),
            title:     title,
            goal:      goal,
            decisions: ((ledger?["critical_decisions"] as? [String]) ?? [])
                           .prefix(kMaxArrayLen).map { $0.truncated(kMaxShortStr) },
            rejected:  ((ledger?["veto_list"] as? [String]) ?? [])
                           .prefix(kMaxArrayLen).map { $0.truncated(kMaxShortStr) },
            state:     (runtime?["current_status"] as? String)?.truncated(kMaxShortStr) ?? "",
            nextStep:  (runtime?["immediate_next_step"] as? String)?.truncated(kMaxLongStr) ?? "",
            llmSource: SnapshotInterchange.normalizeLLM(llmRaw),
            project:   project,
            createdAt: parseDate(d, meta: meta) ?? Date()
        )
    }

    private static func parseDate(_ d: [String: Any], meta: [String: Any]?) -> Date? {
        // Prefer top-level ISO `created_at`, then meta.date (yyyy-MM-dd)
        if let iso = d["created_at"] as? String, let date = parseISO(iso) {
            return date
        }
        if let s = meta?["date"] as? String, let date = parseDateOnly(s) {
            return date
        }
        return nil
    }

    // Browser exports (JS toISOString) carry fractional seconds, iOS exports don't —
    // a plain ISO8601DateFormatter rejects the former, silently resetting dates.
    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    // en_US_POSIX so "yyyy-MM-dd" parses correctly regardless of the device calendar
    private static func parseDateOnly(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}

private extension String {
    func truncated(_ max: Int) -> String { count <= max ? self : String(prefix(max)) }
}
