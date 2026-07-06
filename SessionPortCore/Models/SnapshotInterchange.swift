import Foundation
import CryptoKit

/// Produces backup JSON in the SAME format the browser extension reads/writes
/// (schema_version 1, nested `payload` with meta/core/ledger/runtime).
/// This makes iOS ⇄ browser transfers fully round-trippable.
///
/// Note: binary file attachments (snapshot_files/blobs) are not cross-exported
/// in v1 — only the textual context anchors transfer. The arrays are emitted
/// empty so the extension importer accepts the file without error.
enum SnapshotInterchange {

    static func exportJSON(_ snapshots: [Snapshot], prettyPrinted: Bool = true) -> Data {
        let iso = ISO8601DateFormatter()
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.locale = Locale(identifier: "en_US_POSIX")

        let records: [[String: Any]] = snapshots.map { snap in
            var meta: [String: Any] = [
                "transfer_id": snap.id,
                "project": snap.project ?? "",
                "version": "1.1",
                "date": dateOnly.string(from: snap.createdAt),
                "llm_source": snap.llmSource,
            ]
            if let parent = snap.parentId { meta["parent_transfer_id"] = parent }

            var payload: [String: Any]

            // Full-fidelity path: the model's JSON stored verbatim IS the payload —
            // exactly what the extension itself would have saved from capture.
            if let rawStr = snap.rawPayload,
               let rawData = rawStr.data(using: .utf8),
               let rawDict = (try? JSONSerialization.jsonObject(with: rawData)) as? [String: Any] {
                payload = rawDict
                if payload["meta"] == nil { payload["meta"] = meta }
                // Legacy anchors for pre-v1.1 readers — only if absent in the raw.
                if payload["core"] == nil { payload["core"] = ["intent": snap.goal] }
                if payload["ledger"] == nil {
                    payload["ledger"] = [
                        "critical_decisions": snap.decisions,
                        "veto_list": snap.rejected,
                    ]
                }
                if payload["runtime"] == nil {
                    payload["runtime"] = [
                        "current_status": snap.state,
                        "immediate_next_step": snap.nextStep,
                        "last_3_decisions": Array(snap.decisions.prefix(3)),
                    ]
                }
            } else {
                // Fallback: rebuild from typed fields (snapshots without raw payload).
                payload = [
                    "meta": meta,
                    "core": ["intent": snap.goal],
                    "ledger": [
                        "critical_decisions": snap.decisions,
                        "veto_list": snap.rejected,
                    ],
                    "runtime": [
                        "current_status": snap.state,
                        "immediate_next_step": snap.nextStep,
                        "last_3_decisions": Array(snap.decisions.prefix(3)),
                    ],
                ]

                // Rich v1.1 fields — emitted alongside the legacy anchors (only when
                // present) so both v1.1 readers and legacy readers find their keys.
                var dna: [String: Any] = [:]
                if let t = snap.trajectory, !t.isEmpty { dna["trajectory"] = t }
                if !snap.constraints.isEmpty { dna["constraints"] = snap.constraints }
                if !dna.isEmpty {
                    dna["goal"] = snap.goal
                    payload["dna"] = dna
                }
                if !snap.instructions.isEmpty { payload["instructions"] = snap.instructions }
                if !snap.openThreads.isEmpty  { payload["open_threads"] = snap.openThreads }
                if !snap.artifacts.isEmpty    { payload["state"] = ["artifacts": snap.artifacts] }
                if let v = snap.validation {
                    payload["validation"] = ["questions": v.questions, "expected": v.expected]
                }
            }

            // content_hash over a deterministic payload serialization (matches
            // the extension's sha256(JSON.stringify(payload)) closely enough for dedup)
            let payloadData = (try? JSONSerialization.data(
                withJSONObject: payload, options: [.sortedKeys])) ?? Data()
            let hash = SHA256.hash(data: payloadData)
                .map { String(format: "%02x", $0) }.joined()

            var record: [String: Any] = [
                "snapshot_id": snap.id,
                "created_at": iso.string(from: snap.createdAt),
                "source_host": snap.llmSource,
                "project": snap.project ?? "unknown",
                "version": "1.1",
                "transfer_id": snap.id,
                "content_hash": hash,
                "payload": payload,
                "size_bytes": payloadData.count,
            ]
            if let parent = snap.parentId { record["parent_transfer_id"] = parent }
            // Lifecycle fields — deletions/restores propagate between devices
            // via state_at last-write-wins (extension's applySyncMerge contract).
            if let del = snap.deletedAt { record["deleted_at"] = iso.string(from: del) }
            if let st  = snap.stateAt   { record["state_at"]   = iso.string(from: st) }
            return record
        }

        let wrapper: [String: Any] = [
            "schema_version": 1,
            "exported_at": iso.string(from: Date()),
            "app": "SessionPort iOS",
            "snapshots": records,
            "refs": [],
            "meta": [],
            "snapshot_files": [],
            "blobs": [],
        ]

        let options: JSONSerialization.WritingOptions = prettyPrinted ? [.prettyPrinted] : []
        return (try? JSONSerialization.data(withJSONObject: wrapper, options: options)) ?? Data()
    }

    /// Normalizes a browser host or llm name to the iOS short name.
    static func normalizeLLM(_ raw: String?) -> String {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return "unknown" }
        if raw.contains("claude")      { return "claude" }
        if raw.contains("openai") || raw.contains("chatgpt") { return "chatgpt" }
        if raw.contains("gemini") || raw.contains("bard") || raw.contains("google") { return "gemini" }
        if raw.contains("perplexity")  { return "perplexity" }
        if raw.contains("grok") || raw.contains("x.com") || raw.contains("twitter") { return "grok" }
        if raw.contains("mistral")     { return "mistral" }
        if raw.contains("deepseek")    { return "deepseek" }
        return raw
    }
}
