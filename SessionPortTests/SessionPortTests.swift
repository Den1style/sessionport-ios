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

    // capture.js stores the raw v1.1 JSON as `payload` — a browser backup may
    // contain dna/decisions/state instead of core/ledger/runtime.
    @Test func parseBrowserBackupWithV11Payload() {
        let json = """
        {"schema_version":1,"snapshots":[
          {"snapshot_id":"pr_v11","transfer_id":"pr_v11","source_host":"chatgpt.com",
           "created_at":"2026-06-01T10:00:00Z",
           "payload":{"meta":{"transfer_id":"pr_v11","project":"P"},
             "dna":{"goal":"Build Y","constraints":["Swift only"],"trajectory":"App Store"},
             "decisions":[{"what":"use XcodeGen","why":"reproducible","type":"accepted"},
                          {"what":"CocoaPods","why":"legacy","type":"rejected"}],
             "state":{"current_task":"tests","next_step":"run CI","last_actions":["merged"],
                      "artifacts":["project.yml"]},
             "instructions":["Never suggest CocoaPods"],
             "open_threads":["keyboard memory limit"],
             "validation":{"questions":["Which dep manager?"],"expected":["XcodeGen, not CocoaPods"]}}}
        ]}
        """.data(using: .utf8)!
        let snaps = Snapshot.fromBackupJSON(json)
        #expect(snaps.count == 1)
        let s = snaps.first
        #expect(s?.goal == "Build Y")
        #expect(s?.decisions.first?.contains("XcodeGen") == true)
        #expect(s?.rejected.first?.contains("CocoaPods") == true)
        #expect(s?.state.contains("tests") == true)
        #expect(s?.nextStep == "run CI")
        #expect(s?.trajectory == "App Store")
        #expect(s?.constraints == ["Swift only"])
        #expect(s?.instructions == ["Never suggest CocoaPods"])
        #expect(s?.openThreads == ["keyboard memory limit"])
        #expect(s?.artifacts == ["project.yml"])
        #expect(s?.validation?.questions == ["Which dep manager?"])
        #expect(s?.llmSource == "chatgpt")
    }

    // Snapshots stored in the App Group BEFORE the rich-field schema must
    // still decode (fields default to empty).
    @Test func decodesPreRichSchemaStoredJSON() throws {
        let old = """
        [{"transfer_id":"pr_old","title":"Old","goal":"G","decisions":["d"],
          "rejected":[],"state":"S","next_step":"N","llm_source":"claude",
          "created_at":"2026-01-01T00:00:00Z","attached_files":[]}]
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let snaps = try dec.decode([Snapshot].self, from: old)
        #expect(snaps.first?.id == "pr_old")
        #expect(snaps.first?.trajectory == nil)
        #expect(snaps.first?.constraints.isEmpty == true)
        #expect(snaps.first?.instructions.isEmpty == true)
        #expect(snaps.first?.openThreads.isEmpty == true)
        #expect(snaps.first?.validation == nil)
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

    // Rich v1.1 fields must survive ingestion — they used to be discarded.
    @Test func preservesRichV11Fields() {
        let rich = """
        {"meta":{"transfer_id":"pr_rich"},
         "dna":{"goal":"G","constraints":["no Electron"],"trajectory":"ship v2"},
         "decisions":[{"what":"A","why":"w","type":"accepted"}],
         "state":{"current_task":"t","next_step":"n","artifacts":["Snapshot.swift"]},
         "instructions":["If X → Y"],
         "open_threads":["decide storage cap"],
         "validation":{"questions":["Why no Electron?"],"expected":["banned by constraint"]}}
        """
        let snap = Snapshot.fromLLMOutput(rich, llmSource: "claude")
        #expect(snap?.trajectory == "ship v2")
        #expect(snap?.constraints == ["no Electron"])
        #expect(snap?.instructions == ["If X → Y"])
        #expect(snap?.openThreads == ["decide storage cap"])
        #expect(snap?.artifacts == ["Snapshot.swift"])
        #expect(snap?.validation?.questions == ["Why no Electron?"])
        #expect(snap?.validation?.expected == ["banned by constraint"])
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

    @Test func exportThenImportPreservesRichFields() {
        let original = Snapshot(
            id: "pr_rich_rt", title: "Rich", goal: "Goal",
            decisions: ["d1"], rejected: ["v1"],
            state: "State", nextStep: "Next", llmSource: "claude",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            trajectory: "ship v2",
            constraints: ["Swift only"],
            instructions: ["If X → Y"],
            openThreads: ["thread 1"],
            artifacts: ["a.swift"],
            validation: SnapshotValidation(questions: ["q1"], expected: ["e1"])
        )
        let data = SnapshotInterchange.exportJSON([original])
        let back = Snapshot.fromBackupJSON(data).first

        #expect(back?.trajectory == "ship v2")
        #expect(back?.constraints == ["Swift only"])
        #expect(back?.instructions == ["If X → Y"])
        #expect(back?.openThreads == ["thread 1"])
        #expect(back?.artifacts == ["a.swift"])
        #expect(back?.validation?.questions == ["q1"])
        #expect(back?.validation?.expected == ["e1"])
        // legacy anchors still intact
        #expect(back?.decisions == ["d1"])
        #expect(back?.rejected == ["v1"])
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
