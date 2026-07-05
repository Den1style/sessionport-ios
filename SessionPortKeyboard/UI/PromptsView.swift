import SwiftUI

struct PromptsView: View {
    let onInsert: (String) -> Void

    @State private var prompts = SharedStorage.shared.activePrompts
    @State private var expandedId: String? = nil

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(prompts) { p in
                    PromptRow(
                        prompt: p,
                        isExpanded: expandedId == p.id,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedId = expandedId == p.id ? nil : p.id
                            }
                        },
                        onInsert: {
                            onInsert(p.insertionText())
                            expandedId = nil
                        }
                    )
                }

                // Hint — keyboard extension can't present sheets
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Create prompts in the SessionPort app")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .onAppear {
            // Reload in case user created prompts in the app
            prompts = SharedStorage.shared.activePrompts
        }
    }
}

// MARK: - PromptRow

struct PromptRow: View {
    let prompt: PromptItem
    let isExpanded: Bool
    let onTap: () -> Void
    let onInsert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Text(prompt.isFavorite ? "⭐" : "📝")
                        .font(.system(size: 16))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !isExpanded {
                            Text(prompt.body)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.horizontal, 12)

                Text(prompt.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                if !prompt.attachedFiles.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(prompt.attachedFiles.count) file\(prompt.attachedFiles.count == 1 ? "" : "s") attached")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }

                HStack {
                    Spacer()
                    Button(action: onInsert) {
                        Text("Insert ↑")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(
            isExpanded
                ? Color(red: 0.12, green: 0.1, blue: 0.28)
                : Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
