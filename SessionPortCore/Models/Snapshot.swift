import Foundation

private let kMaxShortStr  = 500
private let kMaxLongStr   = 5_000
private let kMaxArrayLen  = 100
private let kMaxFileSize  = 5 * 1024 * 1024  // 5 MB per file
private let kMaxFiles     = 20

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
    var createdAt: Date
    var attachedFiles: [AttachedFile]

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
        createdAt: Date = Date(),
        attachedFiles: [AttachedFile] = []
    ) {
        self.id = id; self.parentId = parentId; self.title = title
        self.goal = goal; self.decisions = decisions; self.rejected = rejected
        self.state = state; self.nextStep = nextStep; self.llmSource = llmSource
        self.createdAt = createdAt; self.attachedFiles = attachedFiles
    }

    enum CodingKeys: String, CodingKey {
        case id = "transfer_id"; case parentId = "parent_transfer_id"
        case title, goal, decisions, rejected, state
        case nextStep = "next_step"; case llmSource = "llm_source"
        case createdAt = "created_at"; case attachedFiles = "attached_files"
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
}

// MARK: - Parsing

extension Snapshot {
    static func fromBackupJSON(_ data: Data) -> [Snapshot] {
        guard data.count <= 10 * 1024 * 1024,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snaps = obj["snapshots"] as? [[String: Any]] else { return [] }
        return snaps.prefix(500).compactMap { fromRawDict($0) }
    }

    static func fromRawDict(_ d: [String: Any]) -> Snapshot? {
        guard let id = (d["transfer_id"] as? String)?.truncated(kMaxShortStr), !id.isEmpty,
              let title = (d["title"] as? String)?.truncated(kMaxShortStr) else { return nil }

        let runtime = d["runtime"] as? [String: Any]
        let ledger  = d["ledger"]  as? [String: Any]
        let core    = d["core"]    as? [String: Any]

        return Snapshot(
            id:        id,
            parentId:  (d["parent_transfer_id"] as? String)?.truncated(kMaxShortStr),
            title:     title,
            goal:      (core?["intent"] as? String)?.truncated(kMaxLongStr) ?? "",
            decisions: ((ledger?["critical_decisions"] as? [String]) ?? [])
                           .prefix(kMaxArrayLen).map { $0.truncated(kMaxShortStr) },
            rejected:  ((ledger?["veto_list"] as? [String]) ?? [])
                           .prefix(kMaxArrayLen).map { $0.truncated(kMaxShortStr) },
            state:     (runtime?["current_status"] as? String)?.truncated(kMaxShortStr) ?? "",
            nextStep:  (runtime?["immediate_next_step"] as? String)?.truncated(kMaxLongStr) ?? "",
            llmSource: (d["llm_source"] as? String)?.truncated(50) ?? "unknown",
            createdAt: parseDate(d) ?? Date()
        )
    }

    private static func parseDate(_ d: [String: Any]) -> Date? {
        guard let meta = d["meta"] as? [String: Any], let s = meta["date"] as? String else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}

private extension String {
    func truncated(_ max: Int) -> String { count <= max ? self : String(prefix(max)) }
}
