import SwiftUI

struct PromptsView: View {
    let onInsert: (String) -> Void

    @State private var prompts = SharedStorage.shared.prompts
    @State private var expandedId: String? = nil
    @State private var showNew = false
    @State private var newTitle = ""
    @State private var newBody = ""

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
                        },
                        onDelete: {
                            SharedStorage.shared.deletePrompt(id: p.id)
                            prompts = SharedStorage.shared.prompts
                            if expandedId == p.id { expandedId = nil }
                        }
                    )
                }
                // New prompt button
                Button { showNew = true } label: {
                    Label("New prompt", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 180)
        .sheet(isPresented: $showNew) { newPromptSheet }
    }

    private var newPromptSheet: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("Prompt title", text: $newTitle) }
                Section("Body (use {{variable}} for placeholders)") {
                    TextEditor(text: $newBody).frame(minHeight: 100)
                }
            }
            .navigationTitle("New Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showNew = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !newTitle.isEmpty, !newBody.isEmpty else { return }
                        let p = PromptItem(title: String(newTitle.prefix(100)), body: String(newBody.prefix(2000)))
                        SharedStorage.shared.addPrompt(p)
                        prompts = SharedStorage.shared.prompts
                        newTitle = ""; newBody = ""
                        showNew = false
                    }
                    .disabled(newTitle.isEmpty || newBody.isEmpty)
                }
            }
        }
    }
}

// MARK: - PromptRow — matches mockup (indigo expanded bg, Insert ↑ button)

struct PromptRow: View {
    let prompt: PromptItem
    let isExpanded: Bool
    let onTap: () -> Void
    let onInsert: () -> Void
    let onDelete: () -> Void

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
                Divider().overlay(Color.white.opacity(0.08)).padding(.horizontal, 12)
                Text(prompt.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                HStack {
                    Spacer()
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    Button(action: onInsert) {
                        HStack(spacing: 4) {
                            Text("Insert ↑").font(.system(size: 12, weight: .semibold))
                        }
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
