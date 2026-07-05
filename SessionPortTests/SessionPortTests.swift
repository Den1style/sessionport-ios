import Testing
import Foundation
@testable import SessionPort

// MARK: - Snapshot backup parsing

@Suite struct SnapshotTests {

    @Test func parseValidBackup() {
        let json = """
        {"schema_version":1,"snapshots":[
          {"transfer_id":"abc123","title":"Test",
           "core":{"intent":"Goal"},
           "runtime":{"current_status":"ACTIVE","immediate_next_step":"next"},
           "ledger":{"critical_decisions":["d1"],"veto_list":["v1"]},
           "meta":{"date":"2026-01-01"}}
        ]}
        """.data(using: .utf8)!
        let snaps = Snapshot.fromBackupJSON(json)
        #expect(snaps.count == 1)
        #expect(snaps[0].id == "abc123")
        #expect(snaps[0].title == "Test")
        #expect(snaps[0].goal == "Goal")
        #expect(snaps[0].decisions == ["d1"])
    }

    // Real browser backup: anchors nested under `payload`, snapshot_id, source_host.
    @Test func parseBrowserBackupWithPayload() {
        let json = """
        {"schema_version":1,"snapshots":[
          {"snapshot_id":"pr_a","transfer_id":"pr_a","source_host":"claude.ai",
           "created_at":"2026-01-01T10:00:00Z",
           "payload":{"meta":{"transfer_id":"pr_a","project":"Proj"},
             "core":{"intent":"Build X"},
             "ledger":{"critical_decisions":["use Swift"],"veto_list":["no Electron"]},
             "runtime":{"current_status":"WIP","immediate_next_step":"ship"}}}
        ]}
        """.data(using: .utf8)!
        let snaps = Snapshot.fromBackupJSON(json)
        #expect(snaps.count == 1)
        #expect(snaps[0].id == "pr_a")
        #expect(snaps[0].goal == "Build X")
        #expect(snaps[0].rejected == ["no Electron"])
        #expect(snaps[0].llmSource == "claude")
        #expect(snaps[0].project == "Proj")
    }

    @Test func rejectsOversizedData() {
        let huge = Data(repeating: 65, count: 11 * 1024 * 1024) // 11 MB
        let snaps = Snapshot.fromBackupJSON(huge)
        #expect(snaps.isEmpty)
    }

    @Test func truncatesLongStrings() {
        let longTitle = String(repeating: "x", count: 1000)
        let dict: [String: Any] = ["transfer_id": "id1", "title": longTitle]
        let snap = Snapshot.fromRawDict(dict)
        #expect(snap?.title.count == 500)
    }

    @Test func contextTextHasMarkers() {
        let snap = Snapshot(id: "t1", parentId: nil, title: "T",
                            goal: "G", decisions: [], rejected: [],
                            state: "S", nextStep: "N",
                            llmSource: "claude", createdAt: Date())
        let text = snap.contextText()
        #expect(text.hasPrefix("---BEGIN CONTEXT---"))
        #expect(text.hasSuffix("---END CONTEXT---"))
    }
}

// MARK: - fromLLMOutput — must handle every shape the model produces

@Suite struct LLMOutputTests {

    private let body = """
    {"meta":{"transfer_id":"pr_llm"},"dna":{"goal":"Make it work"},
     "decisions":[{"what":"A","why":"because","type":"accepted"},
                  {"what":"B","why":"bad idea","type":"rejected"}],
     "state":{"current_task":"coding","next_step":"test","last_actions":["x"]}}
    """

    @Test func withBeginMarkers() {
        let text = "---BEGIN CONTEXT---\n\(body)\n---END CONTEXT---"
        let snap = Snapshot.fromLLMOutput(text, llmSource: "claude")
        #expect(snap?.id == "pr_llm")
        #expect(snap?.goal == "Make it work")
        #expect(snap?.rejected.first?.contains("B") == true)
    }

    @Test func withJSONCodeBlock() {
        let text = "```json\n\(body)\n```"
        let snap = Snapshot.fromLLMOutput(text, llmSource: "chatgpt")
        #expect(snap?.id == "pr_llm")
        #expect(snap?.llmSource == "chatgpt")
    }

    @Test func withBareJSON() {
        let snap = Snapshot.fromLLMOutput(body, llmSource: "gemini")
        #expect(snap?.id == "pr_llm")
        #expect(snap?.goal == "Make it work")
    }

    @Test func withPrefixedText() {
        let text = "Sure! Here is your snapshot:\n\n\(body)\n\nLet me know if you need more."
        let snap = Snapshot.fromLLMOutput(text, llmSource: "claude")
        #expect(snap?.id == "pr_llm")
    }

    @Test func invalidReturnsNil() {
        #expect(Snapshot.fromLLMOutput("no json at all here", llmSource: "claude") == nil)
    }

    // Chat UIs render straight quotes as “smart” ones; selection-copied text
    // must still parse (em-dash markers degrade to the {...} fallback).
    @Test func withSmartQuotesAndEmDashMarkers() {
        let curly = body.replacingOccurrences(of: "\"", with: "\u{201C}")
        let text = "—BEGIN CONTEXT—\n\(curly)\n—END CONTEXT—"
        let snap = Snapshot.fromLLMOutput(text, llmSource: "claude")
        #expect(snap?.id == "pr_llm")
        #expect(snap?.goal == "Make it work")
    }
}

// MARK: - SnapshotInterchange round-trip (iOS ⇄ browser format parity)

@Suite struct InterchangeTests {

    @Test func exportThenImportPreservesData() {
        let original = Snapshot(
            id: "pr_round", parentId: "pr_parent", title: "Round",
            goal: "Goal text", decisions: ["d1", "d2"], rejected: ["v1"],
            state: "State", nextStep: "Next", llmSource: "claude",
            project: "MyProject", createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = SnapshotInterchange.exportJSON([original])
        let back = Snapshot.fromBackupJSON(data)

        #expect(back.count == 1)
        let r = back.first
        #expect(r?.id == "pr_round")
        #expect(r?.parentId == "pr_parent")
        #expect(r?.goal == "Goal text")
        #expect(r?.decisions == ["d1", "d2"])
        #expect(r?.rejected == ["v1"])
        #expect(r?.state == "State")
        #expect(r?.nextStep == "Next")
        #expect(r?.project == "MyProject")
        #expect(r?.llmSource == "claude")
    }

    @Test func exportUsesSchemaVersion1() {
        let data = SnapshotInterchange.exportJSON([])
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((obj?["schema_version"] as? Int) == 1)
    }

    // Prompts export/import (browser sessionport_prompts_v1 format)
    @Test func promptExportImportRoundTrips() {
        let file = AttachedFile(id: "f1", name: "a.txt", mimeType: "text/plain",
                                sizeBytes: 3, base64: "YWJj")
        let active = [PromptItem(id: "pr_p1", title: "T", body: "Body {{x}}",
                                 attachedFiles: [file], isFavorite: true,
                                 createdAt: Date(timeIntervalSince1970: 1_700_000_000))]
        let data = PromptInterchange.exportJSON(active: active, trashed: [])
        // schema present
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((obj?["schema"] as? String) == "sessionport_prompts_v1")
        // round-trip
        let back = PromptInterchange.parse(data)
        #expect(back.count == 1)
        #expect(back.first?.id == "pr_p1")
        #expect(back.first?.body == "Body {{x}}")
        #expect(back.first?.isFavorite == true)
        #expect(back.first?.attachedFiles.first?.name == "a.txt")
    }
}

// MARK: - PromptItem

@Suite struct PromptTests {

    @Test func detectsVariables() {
        let p = PromptItem(title: "t", body: "Hello {{name}}, you are {{role}}.")
        #expect(p.variables == ["name", "role"])
    }

    @Test func resolvesVariables() {
        let p = PromptItem(title: "t", body: "Hi {{name}}!")
        let resolved = p.resolved(with: ["name": "Claude"])
        #expect(resolved == "Hi Claude!")
    }

    @Test func noVariables() {
        let p = PromptItem(title: "t", body: "Plain text")
        #expect(p.variables.isEmpty)
    }
}

// MARK: - SharedStorage (singleton → main-actor isolated)

@MainActor
@Suite struct StorageTests {

    @Test func addAndPermanentlyDeleteRoundTrips() {
        let storage = SharedStorage.shared
        let initial = storage.snapshots.count
        let snap = Snapshot(id: UUID().uuidString, parentId: nil,
                            title: "Cap test", goal: "", decisions: [],
                            rejected: [], state: "", nextStep: "",
                            llmSource: "test", createdAt: Date())
        storage.addSnapshot(snap)
        #expect(storage.snapshots.count == initial + 1)
        #expect(storage.snapshots.count <= 200)
        storage.permanentlyDelete(id: snap.id)
        #expect(storage.snapshots.count == initial)
    }

    @Test func moveToTrashKeepsButHides() {
        let storage = SharedStorage.shared
        let snap = Snapshot(id: UUID().uuidString, parentId: nil,
                            title: "Trash test", goal: "", decisions: [],
                            rejected: [], state: "", nextStep: "",
                            llmSource: "test", createdAt: Date())
        storage.addSnapshot(snap)
        storage.moveToTrash(id: snap.id)
        #expect(storage.activeSnapshots.contains { $0.id == snap.id } == false)
        #expect(storage.trashedSnapshots.contains { $0.id == snap.id })
        storage.permanentlyDelete(id: snap.id)
    }
}
