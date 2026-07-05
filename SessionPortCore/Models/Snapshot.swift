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

// validation block of the v1.1 protocol — questions probe real decisions so a
// wrong or partial restore yields a visibly wrong answer (see extension v1.0.3)
struct SnapshotValidation: Codable, Hashable {
    var questions: [String]
    var expected: [String]
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

    // ── Rich v1.1 fields (extension parity) — optional for App Group back-compat ──
    var trajectory: String?           // dna.trajectory — where the project is heading
    var constraints: [String]         // dna.constraints — global restrictions
    var instructions: [String]        // behavioral rules for the new model ("If X → Y")
    var openThreads: [String]         // open_threads — genuinely unresolved questions
    var artifacts: [String]           // state.artifacts — files/functions/concepts in play
    var validation: SnapshotValidation?

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
        attachedFiles: [AttachedFile] = [],
        trajectory: String? = nil,
        constraints: [String] = [],
        instructions: [String] = [],
        openThreads: [String] = [],
        artifacts: [String] = [],
        validation: SnapshotValidation? = nil
    ) {
        self.id = id; self.parentId = parentId; self.title = title
        self.goal = goal; self.decisions = decisions; self.rejected = rejected
        self.state = state; self.nextStep = nextStep; self.llmSource = llmSource
        self.project = project; self.createdAt = createdAt
        self.deletedAt = deletedAt; self.attachedFiles = attachedFiles
        self.trajectory = trajectory; self.constraints = constraints
        self.instructions = instructions; self.openThreads = openThreads
        self.artifacts = artifacts; self.validation = validation
    }

    enum CodingKeys: String, CodingKey {
        case id = "transfer_id"; case parentId = "parent_transfer_id"
        case title, goal, decisions, rejected, state, project
        case nextStep = "next_step"; case llmSource = "llm_source"
        case createdAt = "created_at"; case deletedAt = "deleted_at"
        case attachedFiles = "attached_files"
        case trajectory, constraints, instructions, artifacts, validation
        case openThreads = "open_threads"
    }

    // Custom decode: rich fields are decodeIfPresent so snapshots stored in the
    // App Group BEFORE this schema (and schema v2 exports without them) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self, forKey: .id)
        parentId      = try c.decodeIfPresent(String.self, forKey: .parentId)
        title         = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        goal          = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        decisions     = try c.decodeIfPresent([String].self, forKey: .decisions) ?? []
        rejected      = try c.decodeIfPresent([String].self, forKey: .rejected) ?? []
        state         = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        nextStep      = try c.decodeIfPresent(String.self, forKey: .nextStep) ?? ""
        llmSource     = try c.decodeIfPresent(String.self, forKey: .llmSource) ?? ""
        project       = try c.decodeIfPresent(String.self, forKey: .project)
        createdAt     = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        deletedAt     = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        attachedFiles = try c.decodeIfPresent([AttachedFile].self, forKey: .attachedFiles) ?? []
        trajectory    = try c.decodeIfPresent(String.self, forKey: .trajectory)
        constraints   = try c.decodeIfPresent([String].self, forKey: .constraints) ?? []
        instructions  = try c.decodeIfPresent([String].self, forKey: .instructions) ?? []
        openThreads   = try c.decodeIfPresent([String].self, forKey: .openThreads) ?? []
        artifacts     = try c.decodeIfPresent([String].self, forKey: .artifacts) ?? []
        validation    = try c.decodeIfPresent(SnapshotValidation.self, forKey: .validation)
    }

    // Custom encode: rich fields are emitted only when non-empty, so contextText()
    // for older/simple snapshots stays exactly as compact as before.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encode(title, forKey: .title)
        try c.encode(goal, forKey: .goal)
        try c.encode(decisions, forKey: .decisions)
        try c.encode(rejected, forKey: .rejected)
        try c.encode(state, forKey: .state)
        try c.encode(nextStep, forKey: .nextStep)
        try c.encode(llmSource, forKey: .llmSource)
        try c.encodeIfPresent(project, forKey: .project)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(attachedFiles, forKey: .attachedFiles)
        if let t = trajectory, !t.isEmpty { try c.encode(t, forKey: .trajectory) }
        if !constraints.isEmpty  { try c.encode(constraints,  forKey: .constraints) }
        if !instructions.isEmpty { try c.encode(instructions, forKey: .instructions) }
        if !openThreads.isEmpty  { try c.encode(openThreads,  forKey: .openThreads) }
        if !artifacts.isEmpty    { try c.encode(artifacts,    forKey: .artifacts) }
        try c.encodeIfPresent(validation, forKey: .validation)
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
    // mirroring the browser extension's restore flow (v1.0.4 semantics: confirm
    // goal+next_step first, rely only on snapshot data, honor rejections and
    // instructions, keep open_threads alive). Bilingual via kbLangCode.
    @MainActor
    func restoreContext(includeFiles: Bool = true) -> String {
        let isEn = SharedStorage.shared.kbLangCode == "en"
        let preamble = isEn ? """
        SessionPort PROTOCOL — CONTEXT RESTORATION.

        Read the snapshot and restore the working context:
        1. goal — accept as the project's identity; trajectory (if present) is where it's heading
        2. decisions — settled choices; treat as already agreed
        3. rejected — never suggest these again, no matter how reasonable they look
        4. constraints and instructions (if present) — behavioral rules; follow them from the first reply
        5. state — where we are; next_step is your first action; open_threads stay live tasks
        Rely ONLY on snapshot data — if something needed for next_step is missing, ask, don't invent.
        First confirm in one line: goal + next_step. If validation.questions are present, answer them. Then continue from next_step.
        """ : """
        ПРОТОКОЛ SessionPort — ВОССТАНОВЛЕНИЕ КОНТЕКСТА.

        Прочитай слепок и восстанови рабочий контекст:
        1. goal — прими как идентичность проекта; trajectory (если есть) — куда он движется
        2. decisions — принятые решения; считай уже согласованными
        3. rejected — никогда не предлагай это повторно, каким бы разумным оно ни казалось
        4. constraints и instructions (если есть) — правила поведения; соблюдай с первого ответа
        5. state — где мы; next_step — твоё первое действие; open_threads — живые задачи
        Опирайся ТОЛЬКО на данные слепка — если для next_step чего-то не хватает, спроси, не выдумывай.
        Сначала подтверди одной строкой: goal + next_step. Если есть validation.questions — ответь на них. Затем продолжи с next_step.
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

        let (accepted, rejected) = partitionDecisions(decisionsArr)

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

        let rich = richFields(root: obj, dna: dna, state: st)

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
            createdAt: createdAt,
            trajectory: rich.trajectory,
            constraints: rich.constraints,
            instructions: rich.instructions,
            openThreads: rich.openThreads,
            artifacts: rich.artifacts,
            validation: rich.validation
        )
    }

    // ── Shared v1.1 parsing helpers (used by fromLLMOutput and fromRawDict) ──

    // Partition with no data loss: only explicit "rejected" goes to rejected;
    // everything else (accepted, rule, missing/unknown type) → accepted.
    static func partitionDecisions(_ arr: [[String: Any]]) -> (accepted: [String], rejected: [String]) {
        func describe(_ d: [String: Any]) -> String? {
            guard let what = (d["what"] as? String)?.truncated(kMaxShortStr), !what.isEmpty else { return nil }
            if let why = (d["why"] as? String), !why.isEmpty { return "\(what) — \(why)" }
            return what
        }
        let accepted = arr.filter { ($0["type"] as? String) != "rejected" }.compactMap(describe)
        let rejected = arr.filter { ($0["type"] as? String) == "rejected" }.compactMap(describe)
        return (accepted, rejected)
    }

    private struct RichFields {
        var trajectory: String?
        var constraints: [String] = []
        var instructions: [String] = []
        var openThreads: [String] = []
        var artifacts: [String] = []
        var validation: SnapshotValidation?
    }

    // Extracts the rich v1.1 fields the flat schema previously discarded.
    private static func richFields(root: [String: Any], dna: [String: Any]?, state st: [String: Any]?) -> RichFields {
        var r = RichFields()
        r.trajectory = (dna?["trajectory"] as? String)
            .flatMap { $0.isEmpty ? nil : $0.truncated(kMaxLongStr) }
        r.constraints  = strList(dna?["constraints"])
        r.instructions = strList(root["instructions"])
        r.openThreads  = strList(root["open_threads"])
        r.artifacts    = strList(st?["artifacts"])
        if let v = root["validation"] as? [String: Any] {
            let q = strList(v["questions"]), e = strList(v["expected"])
            if !q.isEmpty || !e.isEmpty { r.validation = SnapshotValidation(questions: q, expected: e) }
        }
        return r
    }

    private static func strList(_ any: Any?) -> [String] {
        ((any as? [String]) ?? []).prefix(kMaxArrayLen).map { $0.truncated(kMaxShortStr) }
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
        // Two payload dialects exist in the wild:
        //  • legacy protocol  — core/ledger/runtime
        //  • v1.1 protocol    — dna/decisions/state (what capture.js stores verbatim)
        let payload = d["payload"] as? [String: Any]
        let root    = payload ?? d
        let meta    = (payload?["meta"]    as? [String: Any]) ?? (d["meta"]    as? [String: Any])
        let core    = (payload?["core"]    as? [String: Any]) ?? (d["core"]    as? [String: Any])
        let ledger  = (payload?["ledger"]  as? [String: Any]) ?? (d["ledger"]  as? [String: Any])
        let runtime = (payload?["runtime"] as? [String: Any]) ?? (d["runtime"] as? [String: Any])
        let dna     = (payload?["dna"]     as? [String: Any]) ?? (d["dna"]     as? [String: Any])
        let st      = (payload?["state"]   as? [String: Any]) ?? (d["state"]   as? [String: Any])

        // id: prefer transfer_id (top or meta), fall back to snapshot_id
        let rawId = (d["transfer_id"] as? String)
            ?? (meta?["transfer_id"] as? String)
            ?? (d["snapshot_id"] as? String)
        guard let id = rawId?.truncated(kMaxShortStr), !id.isEmpty else { return nil }

        let goal = ((core?["intent"] as? String) ?? (dna?["goal"] as? String))?
            .truncated(kMaxLongStr) ?? ""
        let project = (meta?["project"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        // decisions/rejected: legacy ledger lists, else partition of v1.1 decisions[]
        var decisions = strList(ledger?["critical_decisions"])
        var rejected  = strList(ledger?["veto_list"])
        if decisions.isEmpty && rejected.isEmpty,
           let arr = root["decisions"] as? [[String: Any]] {
            let (a, r) = partitionDecisions(arr)
            decisions = Array(a.prefix(kMaxArrayLen))
            rejected  = Array(r.prefix(kMaxArrayLen))
        }

        // state: legacy runtime.current_status, else v1.1 current_task + last_actions
        var stateStr = (runtime?["current_status"] as? String)?.truncated(kMaxShortStr) ?? ""
        if stateStr.isEmpty {
            let currentTask = (st?["current_task"] as? String)?.truncated(kMaxShortStr) ?? ""
            let lastActions = (st?["last_actions"] as? [String]) ?? []
            stateStr = ([currentTask] + lastActions.prefix(3))
                .filter { !$0.isEmpty }.joined(separator: " · ").truncated(kMaxShortStr)
        }

        let nextStep = ((runtime?["immediate_next_step"] as? String) ?? (st?["next_step"] as? String))?
            .truncated(kMaxLongStr) ?? ""

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

        let rich = richFields(root: root, dna: dna, state: st)

        return Snapshot(
            id:        id,
            parentId:  (d["parent_transfer_id"] as? String)?.truncated(kMaxShortStr)
                        ?? (meta?["parent_transfer_id"] as? String)?.truncated(kMaxShortStr),
            title:     title,
            goal:      goal,
            decisions: decisions,
            rejected:  rejected,
            state:     stateStr,
            nextStep:  nextStep,
            llmSource: SnapshotInterchange.normalizeLLM(llmRaw),
            project:   project,
            createdAt: parseDate(d, meta: meta) ?? Date(),
            trajectory: rich.trajectory,
            constraints: rich.constraints,
            instructions: rich.instructions,
            openThreads: rich.openThreads,
            artifacts: rich.artifacts,
            validation: rich.validation
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
