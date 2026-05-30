import SwiftUI
import UniformTypeIdentifiers

struct SnapshotDetailView: View {
    @State var snapshot: Snapshot
    @State private var showCopied = false
    @State private var showFilePicker = false
    @State private var fileError: String? = nil

    var body: some View {
        List {
            if !snapshot.goal.isEmpty {
                Section("Goal") { Text(snapshot.goal) }
            }
            if !snapshot.decisions.isEmpty {
                Section("Decisions") {
                    ForEach(snapshot.decisions, id: \.self) { d in
                        Label(d, systemImage: "checkmark.circle.fill").foregroundStyle(.green, .primary)
                    }
                }
            }
            if !snapshot.rejected.isEmpty {
                Section("Rejected") {
                    ForEach(snapshot.rejected, id: \.self) { r in
                        Label(r, systemImage: "xmark.circle.fill").foregroundStyle(.red, .primary)
                    }
                }
            }
            if !snapshot.state.isEmpty {
                Section("State") { Text(snapshot.state) }
            }
            if !snapshot.nextStep.isEmpty {
                Section("Next Step") {
                    Label(snapshot.nextStep, systemImage: "arrow.right.circle.fill")
                        .foregroundStyle(.accentColor, .primary)
                }
            }

            // ── Files (part of this snapshot) ──
            Section {
                ForEach(snapshot.attachedFiles) { file in
                    HStack(spacing: 10) {
                        FileIcon(mimeType: file.mimeType)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text(file.displaySize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            SharedStorage.shared.removeFile(fileId: file.id, fromSnapshot: snapshot.id)
                            snapshot = SharedStorage.shared.snapshots.first { $0.id == snapshot.id } ?? snapshot
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }

                Button {
                    showFilePicker = true
                } label: {
                    Label("Attach file", systemImage: "paperclip")
                        .foregroundStyle(.accentColor)
                }
            } header: {
                HStack {
                    Text("Files")
                    if !snapshot.attachedFiles.isEmpty {
                        Text("(\(snapshot.attachedFiles.count))")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = snapshot.contextText()
                    showCopied = true
                } label: {
                    Label("Copy context + files", systemImage: "doc.on.clipboard")
                }
                Button {
                    UIPasteboard.general.string = snapshot.contextText(includeFiles: false)
                    showCopied = true
                } label: {
                    Label("Copy context only", systemImage: "doc.on.doc")
                }
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(snapshot.title)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            handleFilePick(result)
        }
        .overlay(alignment: .bottom) {
            if showCopied {
                Text("Copied ✓")
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showCopied = false }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopied)
        .alert("File error", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button("OK") { fileError = nil }
        } message: { Text(fileError ?? "") }
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e): fileError = e.localizedDescription
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { continue }
                guard data.count <= 5 * 1024 * 1024 else {
                    fileError = "\(url.lastPathComponent) exceeds 5 MB limit"
                    continue
                }
                let file = AttachedFile(
                    id: UUID().uuidString,
                    name: url.lastPathComponent,
                    mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream",
                    sizeBytes: data.count,
                    base64: data.base64EncodedString()
                )
                SharedStorage.shared.attachFile(file, toSnapshot: snapshot.id)
            }
            snapshot = SharedStorage.shared.snapshots.first { $0.id == snapshot.id } ?? snapshot
        }
    }
}

struct FileIcon: View {
    let mimeType: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(iconColor.opacity(0.15))
                .frame(width: 30, height: 30)
            Text(iconLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(iconColor)
        }
    }
    private var iconLabel: String {
        if mimeType.contains("pdf") { return "PDF" }
        if mimeType.contains("image") { return "IMG" }
        if mimeType.contains("json") { return "JSON" }
        if mimeType.contains("text") || mimeType.contains("javascript") || mimeType.contains("swift") { return "TXT" }
        return "FILE"
    }
    private var iconColor: Color {
        if mimeType.contains("pdf") { return .red }
        if mimeType.contains("image") { return .purple }
        if mimeType.contains("json") { return .orange }
        return .blue
    }
}
