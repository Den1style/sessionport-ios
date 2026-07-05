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
                TransferStep(index: 0, title: L.t("kb.step.analyze"), subtitle: "Вставит промпт анализа в LLM"),
                TransferStep(index: 1, title: L.t("kb.step.snapshot"), subtitle: "Вставит промпт генерации JSON"),
                TransferStep(index: 2, title: L.t("kb.step.save"), subtitle: "Сохранит снэпшот из буфера в приложение"),
            ]
        case .extended:
            return [
                TransferStep(index: 0, title: L.t("kb.step.prepare"), subtitle: "Подготовительный промпт"),
                TransferStep(index: 1, title: L.t("kb.step.anchors"), subtitle: "Проверка 6 якорей"),
                TransferStep(index: 2, title: L.t("kb.step.snapshot"), subtitle: "Генерация JSON"),
                TransferStep(index: 3, title: L.t("kb.step.save"), subtitle: "Сохранит снэпшот из буфера в приложение"),
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

    // MARK: - Persistence (survives keyboard dismiss/recreate)

    @MainActor
    static func restored() -> TransferFlowState {
        let s = SharedStorage.shared
        guard let raw = s.kbFlowMode, let mode = TransferMode(rawValue: raw) else {
            return .modeSelection
        }
        // Clamp the saved step to the mode's valid range
        let step = min(max(0, s.kbFlowStep), mode.steps.count - 1)
        return .inProgress(mode: mode, step: step)
    }

    @MainActor
    func persist() {
        let s = SharedStorage.shared
        switch self {
        case .modeSelection:
            s.kbFlowMode = nil
            s.kbFlowStep = 0
            s.kbTransferId = nil      // session ended/reset — drop the transfer_id
            s.kbClipCountAtPrompt = -1   // stale clipboard marker would mislight Save
        case .inProgress(let mode, let step):
            s.kbFlowMode = mode.rawValue
            s.kbFlowStep = step
        }
    }

    // Same shape as the browser's generateTransferId(): "pr_" + 16 hex chars.
    static func generateTransferId() -> String {
        let hex = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        return "pr_" + hex
    }
}
