import SwiftUI

struct PromptTrashView: View {
    @State private var trashed = SharedStorage.shared.trashedPrompts
    @State private var showEmptyConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if trashed.isEmpty {
                    ContentUnavailableView(
                        L.t("trash.empty.title"),
                        systemImage: "trash",
                        description: Text(L.t("trash.prompt.empty"))
                    )
                } else {
                    List {
                        ForEach(trashed) { prompt in
                            PromptTrashCard(prompt: prompt, onRestore: {
                                SharedStorage.shared.restorePrompt(id: prompt.id)
                                trashed = SharedStorage.shared.trashedPrompts
                            }, onDelete: {
                                SharedStorage.shared.permanentlyDeletePrompt(id: prompt.id)
                                trashed = SharedStorage.shared.trashedPrompts
                            })
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L.t("trash.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !trashed.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L.t("trash.clear"), role: .destructive) {
                            showEmptyConfirm = true
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .onAppear { trashed = SharedStorage.shared.trashedPrompts }
            .confirmationDialog(
                L.t("trash.clear.title"),
                isPresented: $showEmptyConfirm,
                titleVisibility: .visible
            ) {
                Button("\(L.t("trash.deleteForever")) (\(trashed.count))", role: .destructive) {
                    SharedStorage.shared.emptyPromptsTrash()
                    trashed = []
                }
                Button(L.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(L.t("trash.clear.msg"))
            }
        }
    }
}

struct PromptTrashCard: View {
    let prompt: PromptItem
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if prompt.isFavorite {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                }
                Text(prompt.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if !prompt.attachedFiles.isEmpty {
                    Text("📎 \(prompt.attachedFiles.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Text(prompt.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let deleted = prompt.deletedAt {
                Text("\(L.t("trash.deletedAgo")) \(deleted, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button(action: onRestore) {
                    Label(L.t("common.restore"), systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDelete) {
                    Label(L.t("common.delete"), systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
