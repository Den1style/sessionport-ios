import Foundation

enum TransferMode: String, Codable, CaseIterable {
    case simple   = "simple"
    case extended = "extended"

    var title: String {
        switch self {
        case .simple:   return "Simple"
        case .extended: return "Extended"
        }
    }

    var icon: String {
        switch self {
        case .simple:   return "⚡"
        case .extended: return "🔬"
        }
    }

    var stepCount: Int {
        switch self {
        case .simple:   return 2
        case .extended: return 3
        }
    }

    var steps: [TransferStep] {
        switch self {
        case .simple:
            return [
                TransferStep(index: 0, title: "Save & Send", subtitle: "Captures context and copies to clipboard"),
                TransferStep(index: 1, title: "Load ↑", subtitle: "Inserts context into current LLM"),
            ]
        case .extended:
            return [
                TransferStep(index: 0, title: "Save", subtitle: "Save current conversation state"),
                TransferStep(index: 1, title: "Capture", subtitle: "Validate anchors and clarify"),
                TransferStep(index: 2, title: "Load ↑", subtitle: "Inserts context into current LLM"),
            ]
        }
    }
}

struct TransferStep {
    let index: Int
    let title: String
    let subtitle: String
}

enum TransferFlowState: Equatable {
    case modeSelection
    case inProgress(mode: TransferMode, step: Int)

    var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }
}
