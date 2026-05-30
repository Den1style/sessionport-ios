import Foundation

struct PromptItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var body: String            // supports {{variable}} placeholders
    var attachedFiles: [AttachedFile]
    var isFavorite: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        attachedFiles: [AttachedFile] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id; self.title = title; self.body = body
        self.attachedFiles = attachedFiles
        self.isFavorite = isFavorite; self.createdAt = createdAt
    }

    var variables: [String] {
        let pattern = #"\{\{(\w+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        return regex.matches(in: body, range: range).compactMap {
            Range($0.range(at: 1), in: body).map { String(body[$0]) }
        }
    }

    func resolved(with values: [String: String]) -> String {
        var result = body
        for (key, value) in values { result = result.replacingOccurrences(of: "{{\(key)}}", with: value) }
        return result
    }

    // Full text for insertion: resolved body + file contents
    func insertionText(variableValues: [String: String] = [:]) -> String {
        var text = resolved(with: variableValues)
        for file in attachedFiles {
            if let content = file.textContent() {
                text += "\n\n---FILE: \(file.name)---\n\(content)\n---END FILE---"
            }
        }
        return text
    }
}

extension PromptItem {
    static let demos: [PromptItem] = [
        PromptItem(title: "Deep dive",
                   body: "Let's go deeper. Explore edge cases, failure modes, and alternative approaches I haven't considered yet.",
                   isFavorite: true),
        PromptItem(title: "Summarize context",
                   body: "Summarize the key decisions and next steps from this conversation context."),
        PromptItem(title: "Continue task",
                   body: "Continue from where we left off. The goal is: {{goal}}. Next step: {{next_step}}"),
        PromptItem(title: "Debug assistant",
                   body: "You are a debugging expert. Analyze this {{language}} code and find all bugs:\n\n{{code}}"),
    ]
}
