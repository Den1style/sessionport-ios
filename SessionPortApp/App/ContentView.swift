import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService
    @AppStorage("sp_onboarding_done") private var onboardingDone = false

    var body: some View {
        if !onboardingDone {
            OnboardingView(onDone: { onboardingDone = true })
        } else {
            MainTabView()
                .environmentObject(drive)
                .environmentObject(store)
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService

    var body: some View {
        TabView {
            SnapshotsTab()
                .tabItem { Label("Snapshots", systemImage: "clock.arrow.circlepath") }
                .environmentObject(drive)
                .environmentObject(store)

            PromptsLibraryTab()
                .tabItem { Label("Prompts", systemImage: "pencil.and.list.clipboard") }

            MindMapContainerView()
                .tabItem { Label("Mind Map", systemImage: "brain.head.profile") }

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }
                .environmentObject(drive)
                .environmentObject(store)
        }
    }
}

// MARK: - Snapshots Tab

struct SnapshotsTab: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService
    @State private var snapshots = SharedStorage.shared.snapshots
    @State private var search = ""
    @State private var showPaywall = false

    private var filtered: [Snapshot] {
        search.isEmpty ? snapshots
            : snapshots.filter {
                $0.title.localizedCaseInsensitiveContains(search)
                || $0.goal.localizedCaseInsensitiveContains(search)
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if drive.isConnected {
                    SyncBanner(drive: drive)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }
                if !store.isPro {
                    FreemiumBanner(remaining: SharedStorage.shared.freeSnapshotsRemaining) {
                        showPaywall = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init())
                }
                ForEach(filtered) { snap in
                    NavigationLink(destination: SnapshotDetailView(snapshot: snap)) {
                        SnapshotListRow(snapshot: snap)
                    }
                }
                .onDelete { idx in
                    idx.forEach { SharedStorage.shared.deleteSnapshot(id: filtered[$0].id) }
                    snapshots = SharedStorage.shared.snapshots
                }
            }
            .searchable(text: $search, prompt: "Search snapshots")
            .navigationTitle("Snapshots")
            .toolbar {
                if drive.isConnected {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { Task { await drive.sync() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .symbolEffect(.rotate, isActive: drive.isSyncing)
                        }
                    }
                }
            }
            .refreshable {
                if drive.isConnected { await drive.sync() }
                snapshots = SharedStorage.shared.snapshots
            }
            .onAppear { snapshots = SharedStorage.shared.snapshots }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "Upgrade for unlimited snapshots")
        }
    }
}

// MARK: - Prompts Library Tab

struct PromptsLibraryTab: View {
    @State private var prompts = SharedStorage.shared.prompts
    @State private var showNew = false
    @State private var newTitle = ""
    @State private var newBody = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(prompts) { p in
                    NavigationLink(destination: PromptDetailView(prompt: p)) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                if p.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                }
                                Text(p.title).font(.headline)
                            }
                            Text(p.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            HStack(spacing: 8) {
                                if !p.variables.isEmpty {
                                    Text(p.variables.map { "{{\($0)}}" }.joined(separator: " "))
                                        .font(.caption)
                                        .foregroundStyle(.accentColor)
                                }
                                if !p.attachedFiles.isEmpty {
                                    Text("📎 \(p.attachedFiles.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { idx in
                    idx.forEach { SharedStorage.shared.deletePrompt(id: prompts[$0].id) }
                    prompts = SharedStorage.shared.prompts
                }
            }
            .navigationTitle("Prompts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .onAppear { prompts = SharedStorage.shared.prompts }
        }
        .sheet(isPresented: $showNew) {
            NewPromptSheet { prompt in
                SharedStorage.shared.addPrompt(prompt)
                prompts = SharedStorage.shared.prompts
            }
        }
    }
}

// MARK: - New Prompt Sheet

struct NewPromptSheet: View {
    let onSave: (PromptItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var isFavorite = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Prompt title", text: $title)
                }
                Section("Body (use {{variable}} for placeholders)") {
                    TextEditor(text: $body_).frame(minHeight: 100)
                }
                Section {
                    Toggle("Favourite", isOn: $isFavorite)
                }
            }
            .navigationTitle("New Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !title.isEmpty, !body_.isEmpty else { return }
                        onSave(PromptItem(
                            title: String(title.prefix(100)),
                            body: String(body_.prefix(2000)),
                            isFavorite: isFavorite
                        ))
                        dismiss()
                    }
                    .disabled(title.isEmpty || body_.isEmpty)
                }
            }
        }
    }
}

// MARK: - Prompt Detail View (with files + variables)

struct PromptDetailView: View {
    @State var prompt: PromptItem
    @State private var varValues: [String: String] = [:]
    @State private var showCopied = false
    @State private var showFilePicker = false
    @State private var fileError: String? = nil
    @Environment(\.dismiss) private var dismiss

    var resolved: String { prompt.insertionText(variableValues: varValues) }

    var body: some View {
        List {
            Section("Body") {
                Text(prompt.body).font(.body)
            }

            if !prompt.variables.isEmpty {
                Section("Variables") {
                    ForEach(prompt.variables, id: \.self) { v in
                        HStack {
                            Text("{{\(v)}}")
                                .foregroundStyle(.accentColor)
                                .font(.caption.monospaced())
                            Spacer()
                            TextField("value", text: Binding(
                                get: { varValues[v] ?? "" },
                                set: { varValues[v] = $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }
                Section("Preview") {
                    Text(resolved)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            // Attached files
            Section {
                ForEach(prompt.attachedFiles) { file in
                    HStack(spacing: 10) {
                        FileIcon(mimeType: file.mimeType)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(file.displaySize).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            prompt.attachedFiles.removeAll { $0.id == file.id }
                            SharedStorage.shared.updatePrompt(prompt)
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
                    if !prompt.attachedFiles.isEmpty {
                        Text("(\(prompt.attachedFiles.count))").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = resolved
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showCopied = false }
                    }
                } label: {
                    Label(showCopied ? "Copied ✓" : "Copy & Insert", systemImage: "doc.on.clipboard")
                }

                Toggle("Favourite", isOn: Binding(
                    get: { prompt.isFavorite },
                    set: { prompt.isFavorite = $0; SharedStorage.shared.updatePrompt(prompt) }
                ))
            }
        }
        .navigationTitle(prompt.title)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            handleFilePick(result)
        }
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
                    fileError = "\(url.lastPathComponent) exceeds 5 MB limit"; continue
                }
                let file = AttachedFile(
                    id: UUID().uuidString,
                    name: url.lastPathComponent,
                    mimeType: url.mimeType,
                    sizeBytes: data.count,
                    base64: data.base64EncodedString()
                )
                prompt.attachedFiles.append(file)
            }
            SharedStorage.shared.updatePrompt(prompt)
        }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section("Subscription") {
                    if store.isPro {
                        Label("SessionPort Pro — Active", systemImage: "crown.fill")
                            .foregroundStyle(.yellow)
                    } else {
                        Button { showPaywall = true } label: {
                            HStack {
                                Label("Upgrade to Pro", systemImage: "crown")
                                Spacer()
                                Text("$4.99/mo").foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    Button("Restore purchases") { Task { await store.restorePurchases() } }
                        .foregroundStyle(.accentColor)
                }

                Section("Google Drive") {
                    if drive.isConnected {
                        Label(drive.email ?? "Connected", systemImage: "checkmark.icloud.fill")
                            .foregroundStyle(.green)
                        if let last = drive.lastSync {
                            HStack {
                                Text("Last sync")
                                Spacer()
                                Text(last, style: .relative).foregroundStyle(.secondary)
                            }
                        }
                        Button { Task { await drive.sync() } } label: {
                            HStack {
                                Label("Sync now", systemImage: "arrow.clockwise")
                                if drive.isSyncing { Spacer(); ProgressView().scaleEffect(0.8) }
                            }
                        }
                        .disabled(drive.isSyncing)
                        Button(role: .destructive) { drive.disconnect() } label: {
                            Label("Disconnect", systemImage: "xmark.icloud")
                        }
                    } else {
                        Button { Task { try? await drive.connect() } } label: {
                            Label("Connect Google Drive", systemImage: "icloud.and.arrow.up")
                        }
                        Text("Reads your SessionPort backups. Scope: drive.file only.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com/Den1style/sessionport-ios")!) {
                        Label("GitHub", systemImage: "safari")
                    }
                    Link(destination: URL(string: "https://t.me/SessionPort")!) {
                        Label("Telegram", systemImage: "paperplane")
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "Unlock unlimited snapshots and sync")
        }
    }
}

// MARK: - Shared UI

struct SyncBanner: View {
    @ObservedObject var drive: GoogleDriveService
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.icloud").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(drive.email ?? "Connected").font(.system(size: 13, weight: .medium))
                if let last = drive.lastSync {
                    Text("Synced \(last, style: .relative)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if drive.isSyncing { ProgressView().scaleEffect(0.8) }
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}

struct FreemiumBanner: View {
    let remaining: Int
    let onUpgrade: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(remaining) free snapshot\(remaining == 1 ? "" : "s") left")
                    .font(.system(size: 13, weight: .medium))
                Text("Upgrade for unlimited").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Upgrade", action: onUpgrade)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.accentColor, in: Capsule())
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}

struct SnapshotListRow: View {
    let snapshot: Snapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(llmColor(snapshot.llmSource)).frame(width: 8, height: 8)
                Text(snapshot.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Spacer()
                Text(snapshot.llmSource.capitalized)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            if !snapshot.goal.isEmpty {
                Text(snapshot.goal).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(snapshot.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                if !snapshot.attachedFiles.isEmpty {
                    Text("📎 \(snapshot.attachedFiles.count)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
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
