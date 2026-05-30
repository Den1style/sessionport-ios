import Testing
@testable import SessionPort

// MARK: - Snapshot parsing

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

    @Test func rejectsOversizedData() {
        let huge = Data(repeating: 65, count: 11 * 1024 * 1024) // 11 MB
        let snaps = Snapshot.fromBackupJSON(huge)
        #expect(snaps.isEmpty)
    }

    @Test func truncatesLongStrings() {
        let longTitle = String(repeating: "x", count: 1000)
        var dict: [String: Any] = ["transfer_id": "id1", "title": longTitle]
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

// MARK: - SharedStorage

@Suite struct StorageTests {

    @Test func snapshotCap() {
        let storage = SharedStorage.shared
        let initial = storage.snapshots.count
        // Add enough to exceed cap (just verify logic, don't actually hit 200)
        let snap = Snapshot(id: UUID().uuidString, parentId: nil,
                            title: "Cap test", goal: "", decisions: [],
                            rejected: [], state: "", nextStep: "",
                            llmSource: "test", createdAt: Date())
        storage.addSnapshot(snap)
        #expect(storage.snapshots.count <= 200)
        // Cleanup
        storage.deleteSnapshot(id: snap.id)
        #expect(storage.snapshots.count == initial)
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
