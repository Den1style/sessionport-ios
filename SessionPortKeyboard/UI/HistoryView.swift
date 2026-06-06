import SwiftUI

struct HistoryView: View {
    let onLoad: (Snapshot) -> Void

    @State private var snapshots = SharedStorage.shared.activeSnapshots
    @State private var selected: Snapshot? = nil

    var body: some View {
        Group {
            if let snap = selected {
                detail(snap)
            } else {
                list
            }
        }
        .onAppear {
            snapshots = SharedStorage.shared.activeSnapshots
        }
    }

    // MARK: List — matches mockup (colored dots, LLM name, relative time)

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                if snapshots.isEmpty {
                    Text("Нет снэпшотов")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(snapshots) { snap in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { selected = snap }
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(llmColor(snap.llmSource))
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snap.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(snap.llmSource.isEmpty ? "Unknown" : snap.llmSource.capitalized)
                                        Text("·")
                                        Text(snap.createdAt, style: .relative)
                                    }
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 180)
    }

    // MARK: Detail

    private func detail(_ snap: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation { selected = nil }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("Назад").font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    onLoad(snap)
                    withAnimation { selected = nil }
                } label: {
                    Label("Load ↑", systemImage: "arrow.up.doc.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(llmColor(snap.llmSource)).frame(width: 8, height: 8)
                    Text(snap.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                }
                if !snap.goal.isEmpty {
                    Text(snap.goal)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if !snap.nextStep.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.accentColor)
                        Text(snap.nextStep)
                            .font(.system(size: 11))
                            .foregroundStyle(.accentColor)
                            .lineLimit(2)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func llmColor(_ source: String) -> Color {
        switch source.lowercased() {
        case "claude":     return .orange
        case "chatgpt":    return .green
        case "gemini":     return .blue
        case "grok":       return .primary
        case "perplexity": return .purple
        case "mistral":    return .teal
        default:           return .gray
        }
    }
}
