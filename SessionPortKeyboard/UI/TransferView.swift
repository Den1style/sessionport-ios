import SwiftUI

struct TransferView: View {
    @Binding var flowState: TransferFlowState
    let llmName: String
    let onInsertText: (String) -> Void

    var body: some View {
        Group {
            switch flowState {
            case .modeSelection:      modeSelection
            case .inProgress(let m, let s): stepsView(mode: m, step: s)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    // MARK: Mode cards — match mockup exactly

    private var modeSelection: some View {
        HStack(spacing: 10) {
            ModeCard(
                icon: "⚡", title: "Simple",
                subtitle: "2 шага · быстро",
                bg: Color(red: 0.22, green: 0.14, blue: 0.02),
                accent: Color(red: 1.0, green: 0.75, blue: 0.1)
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    flowState = .inProgress(mode: .simple, step: 0)
                }
            }
            ModeCard(
                icon: "🔬", title: "Extended",
                subtitle: "3 шага · полный контроль",
                bg: Color(red: 0.12, green: 0.1, blue: 0.28),
                accent: Color(red: 0.6, green: 0.5, blue: 1.0)
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    flowState = .inProgress(mode: .extended, step: 0)
                }
            }
        }
    }

    // MARK: Steps

    private func stepsView(mode: TransferMode, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { flowState = .modeSelection }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text("Back").font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                ForEach(Array(mode.steps.enumerated()), id: \.offset) { i, s in
                    StepButton(
                        title: s.title,
                        index: i,
                        state: i < step ? .done : i == step ? .active : .waiting
                    ) { handleStep(mode: mode, index: i, currentStep: step) }
                }
            }
        }
    }

    // MARK: Logic

    private func handleStep(mode: TransferMode, index: Int, currentStep: Int) {
        guard index == currentStep else { return }
        let storage = SharedStorage.shared

        switch mode {
        case .simple:
            if index == 0 {
                guard storage.canAddSnapshot else { return }
                let snap = makeSnapshot()
                storage.addSnapshot(snap)
                UIPasteboard.general.string = snap.contextText()
                advance(mode: mode, from: index)
            } else {
                if let latest = storage.snapshots.first { onInsertText(latest.contextText()) }
                flowState = .modeSelection
            }
        case .extended:
            if index == 0 {
                guard storage.canAddSnapshot else { return }
                storage.addSnapshot(makeSnapshot())
                advance(mode: mode, from: index)
            } else if index == 1 {
                UIPasteboard.general.string = capturePrompt
                advance(mode: mode, from: index)
            } else {
                if let latest = storage.snapshots.first { onInsertText(latest.contextText()) }
                flowState = .modeSelection
            }
        }
    }

    private func advance(mode: TransferMode, from i: Int) {
        let next = i + 1
        withAnimation(.spring(response: 0.22)) {
            flowState = next < mode.steps.count
                ? .inProgress(mode: mode, step: next)
                : .modeSelection
        }
    }

    private func makeSnapshot() -> Snapshot {
        Snapshot(
            id: UUID().uuidString,
            parentId: SharedStorage.shared.snapshots.first?.id,
            title: "Context \(Date().formatted(date: .abbreviated, time: .shortened))",
            goal: "", decisions: [], rejected: [],
            state: "ACTIVE", nextStep: "",
            llmSource: llmName.isEmpty ? "unknown" : llmName.lowercased(),
            createdAt: Date()
        )
    }

    private let capturePrompt = """
        Capture current conversation as SessionPort snapshot. \
        JSON fields: transfer_id, title, goal, decisions[], rejected[], state, next_step.
        """
}

// MARK: - ModeCard

struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let bg: Color
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(icon).font(.system(size: 28))
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(accent.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(bg, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StepButton

enum StepButtonState { case waiting, active, done }

struct StepButton: View {
    let title: String
    let index: Int
    let state: StepButtonState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(dotColor).frame(width: 20, height: 20)
                    if state == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(state == .active ? .white : .secondary)
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: state == .active ? .semibold : .regular))
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(state == .active
                          ? Color.accentColor.opacity(0.13)
                          : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(state == .active ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(state == .waiting)
        .opacity(state == .waiting ? 0.45 : 1)
    }

    private var dotColor: Color {
        switch state {
        case .waiting: .secondary.opacity(0.3)
        case .active:  .accentColor
        case .done:    .green
        }
    }
}
