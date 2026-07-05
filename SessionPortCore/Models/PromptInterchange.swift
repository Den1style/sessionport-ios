import Foundation

/// Export/import prompts in the browser extension's format
/// (`schema: "sessionport_prompts_v1"`), so prompt libraries are portable
/// between the iOS app and the Chrome extension.
///
/// Field mapping (extension ⇄ iOS):
///   prompt_id ⇄ id · title ⇄ title · text ⇄ body · favorite ⇄ isFavorite
///   created_at ⇄ createdAt · files[] (by prompt_id) ⇄ attachedFiles
/// The extension stores one file per prompt; iOS allows several — export emits
/// all, import collects all.
enum PromptInterchange {

    static func exportJSON(active: [PromptItem], trashed: [PromptItem]) -> Data {
        let iso = ISO8601DateFormatter()

        func promptDict(_ p: PromptItem) -> [String: Any] {
            var d: [String: Any] = [
                "prompt_id": p.id,
                "title": p.title,
                "text": p.body,
                "favorite": p.isFavorite,
                "tags": [],
                "created_at": iso.string(from: p.createdAt),
            ]
            if let del = p.deletedAt { d["deleted_at"] = iso.string(from: del) }
            return d
        }

        let files: [[String: Any]] = active.flatMap { p in
            p.attachedFiles.map { f in
                [
                    "prompt_id": p.id,
                    "name": f.name,
                    "mime": f.mimeType,
                    "size": f.sizeBytes,
                    "data_b64": f.base64,
                ]
            }
        }

        // Only recent trash (≤30 days), matching the extension.
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let recentTrash = trashed.filter { ($0.deletedAt ?? .distantPast) > cutoff }

        let wrapper: [String: Any] = [
            "schema": "sessionport_prompts_v1",
            "exported_at": iso.string(from: Date()),
            "app": "SessionPort iOS",
            "prompts": active.map(promptDict),
            "files": files,
            "trash": recentTrash.map(promptDict),
        ]
        return (try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted])) ?? Data()
    }

    /// Returns parsed prompts (active + trashed, with deletedAt set on the latter).
    static func parse(_ data: Data) -> [PromptItem] {
        guard data.count <= 10 * 1024 * 1024,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        // Accept our schema; be lenient about exact string.
        if let schema = obj["schema"] as? String, !schema.contains("sessionport_prompts") {
            return []
        }

        // Group files by prompt_id.
        var filesByPrompt: [String: [AttachedFile]] = [:]
        for f in (obj["files"] as? [[String: Any]] ?? []) {
            guard let pid = f["prompt_id"] as? String else { continue }
            let file = AttachedFile(
                id: UUID().uuidString,
                name: (f["name"] as? String) ?? "file",
                mimeType: (f["mime"] as? String) ?? "application/octet-stream",
                sizeBytes: (f["size"] as? Int) ?? 0,
                base64: (f["data_b64"] as? String) ?? ""
            )
            filesByPrompt[pid, default: []].append(file)
        }

        let isoFull = ISO8601DateFormatter()
        // Browser exports (JS toISOString) include fractional seconds — the plain
        // formatter rejects those, which would silently reset dates to "now".
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func parseDate(_ s: Any?) -> Date? {
            guard let str = s as? String else { return nil }
            return isoFull.date(from: str) ?? isoFrac.date(from: str)
        }

        func makePrompt(_ d: [String: Any], trashed: Bool) -> PromptItem? {
            guard let id = d["prompt_id"] as? String, !id.isEmpty else { return nil }
            // Extension uses "text"; tolerate "body" too.
            let body = (d["text"] as? String) ?? (d["body"] as? String) ?? ""
            return PromptItem(
                id: id,
                title: (d["title"] as? String) ?? "Prompt",
                body: body,
                attachedFiles: filesByPrompt[id] ?? [],
                isFavorite: (d["favorite"] as? Bool) ?? false,
                createdAt: parseDate(d["created_at"]) ?? Date(),
                deletedAt: trashed ? (parseDate(d["deleted_at"]) ?? Date()) : nil
            )
        }

        var result: [PromptItem] = []
        for d in (obj["prompts"] as? [[String: Any]] ?? []) {
            if let p = makePrompt(d, trashed: false) { result.append(p) }
        }
        for d in (obj["trash"] as? [[String: Any]] ?? []) {
            if let p = makePrompt(d, trashed: true) { result.append(p) }
        }
        return Array(result.prefix(1000))
    }
}
