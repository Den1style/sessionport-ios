import SwiftUI

struct TrashView: View {
    @State private var trashed = SharedStorage.shared.trashedSnapshots
    @State private var showEmptyConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if trashed.isEmpty {
                    ContentUnavailableView(
                        "Корзина пуста",
                        systemImage: "trash",
                        description: Text("Удалённые снэпшоты появятся здесь")
                    )
                } else {
                    List {
                        ForEach(trashed) { snap in
                            TrashCard(snapshot: snap, onRestore: {
                                SharedStorage.shared.restoreFromTrash(id: snap.id)
                                trashed = SharedStorage.shared.trashedSnapshots
                            }, onDelete: {
                                SharedStorage.shared.permanentlyDelete(id: snap.id)
                                trashed = SharedStorage.shared.trashedSnapshots
                            })
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Корзина")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !trashed.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Очистить", role: .destructive) {
                            showEmptyConfirm = true
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .onAppear { trashed = SharedStorage.shared.trashedSnapshots }
            .confirmationDialog(
                "Очистить корзину?",
                isPresented: $showEmptyConfirm,
                titleVisibility: .visible
            ) {
                Button("Удалить навсегда (\(trashed.count))", role: .destructive) {
                    SharedStorage.shared.emptyTrash()
                    trashed = []
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Это действие необратимо.")
            }
        }
    }
}

struct TrashCard: View {
    let snapshot: Snapshot
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(llmColor(snapshot.llmSource)).frame(width: 8, height: 8)
                Text(snapshot.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if let proj = snapshot.project {
                    Text(proj)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }

            if let deleted = snapshot.deletedAt {
                Text("Удалено \(deleted, style: .relative) назад")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(action: onRestore) {
                    Label("Восстановить", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDelete) {
                    Label("Удалить", systemImage: "trash")
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

    private func llmColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "claude": return .orange
        case "chatgpt": return .green
        case "gemini": return .blue
        case "grok": return .primary
        case "perplexity": return .purple
        default: return .gray
        }
    }
}
