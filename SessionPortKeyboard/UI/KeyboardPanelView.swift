import SwiftUI

enum KeyboardTab { case transfer, prompts }
enum PanelScreen { case main, history }

struct KeyboardPanelView: View {
    let llmName: String
    let onInsertText: (String) -> Void
    let onCollapse: () -> Void

    @State private var activeTab: KeyboardTab = .transfer
    @State private var screen: PanelScreen = .main
    @State private var flowState: TransferFlowState = .modeSelection

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            content
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            // History icon — purple circle
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    screen = screen == .history ? .main : .history
                    if screen == .main { flowState = .modeSelection }
                }
            } label: {
                ZStack {
                    Circle().fill(Color(red: 0.44, green: 0.33, blue: 0.85))
                        .frame(width: 32, height: 32)
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            if screen == .main {
                // Tab pills
                HStack(spacing: 3) {
                    tabPill(label: "—— Transfer", tab: .transfer, activeColor: Color(red: 0.85, green: 0.55, blue: 0.1))
                    tabPill(label: "✏️ Prompts", tab: .prompts, activeColor: Color(red: 0.44, green: 0.33, blue: 0.85))
                }
            } else {
                Text("ИСТОРИЯ СНЭПШОТОВ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }

            Spacer()

            // LLM dot indicator
            if !llmName.isEmpty {
                HStack(spacing: 5) {
                    Circle().fill(llmColor(llmName)).frame(width: 8, height: 8)
                    Text(llmName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Collapse
            Button(action: onCollapse) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func tabPill(label: String, tab: KeyboardTab, activeColor: Color) -> some View {
        let isActive = activeTab == tab && screen == .main
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeTab = tab
                flowState = .modeSelection
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? activeColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .history:
            HistoryView { snap in onInsertText(snap.contextText()) }
        case .main:
            switch activeTab {
            case .transfer:
                TransferView(flowState: $flowState, onInsertText: onInsertText)
            case .prompts:
                PromptsView(onInsert: onInsertText)
            }
        }
    }

    // MARK: LLM color

    private func llmColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "claude":     return .orange
        case "chatgpt":    return .green
        case "gemini":     return .blue
        case "grok":       return .primary
        case "perplexity": return .purple
        default:           return .gray
        }
    }
}
