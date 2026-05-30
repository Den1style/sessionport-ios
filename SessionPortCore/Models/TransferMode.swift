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
        case .simple:   return 3
        case .extended: return 4
        }
    }

    var steps: [TransferStep] {
        switch self {
        case .simple:
            return [
                TransferStep(index: 0, title: "Анализ", subtitle: "Вставит промпт анализа в LLM"),
                TransferStep(index: 1, title: "Слепок", subtitle: "Вставит промпт генерации JSON"),
                TransferStep(index: 2, title: "Load ↑", subtitle: "Вставит контекст в новый LLM"),
            ]
        case .extended:
            return [
                TransferStep(index: 0, title: "Подготовка", subtitle: "Подготовительный промпт"),
                TransferStep(index: 1, title: "Якоря", subtitle: "Проверка 6 якорей"),
                TransferStep(index: 2, title: "Слепок", subtitle: "Генерация JSON"),
                TransferStep(index: 3, title: "Load ↑", subtitle: "Вставит контекст в новый LLM"),
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
