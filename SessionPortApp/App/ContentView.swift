import SwiftUI

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

// MARK: - Main Tab View (mirrors browser extension features)

struct MainTabView: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService

    var body: some View {
        TabView {
            SnapshotsTab()
                .tabItem { Label("Snapshots", systemImage: "clock.arrow.circlepath") }

            PromptsLibraryTab()
                .tabItem { Label("Prompts", systemImage: "pencil.and.list.clipboard") }

            FilesTab()
                .tabItem { Label("Files", systemImage: "doc.on.doc") }

            MindMapTab()
                .tabItem { Label("Map", systemImage: "point.3.connected.trianglepath.dotted") }

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .environmentObject(drive)
        .environmentObject(store)
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
                        Button {
                            Task { await drive.sync() }
                        } label: {
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

// MARK: - Snapshot Detail

struct SnapshotDetailView: View {
    let snapshot: Snapshot
    @State private var showCopied = false

    var body: some View {
        List {
            if !snapshot.goal.isEmpty {
                Section("Goal") { Text(snapshot.goal).font(.body) }
            }
            if !snapshot.decisions.isEmpty {
                Section("Decisions (\(snapshot.decisions.count))") {
                    ForEach(snapshot.decisions, id: \.self) { d in
                        Label(d, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green, .primary)
                    }
                }
            }
            if !snapshot.rejected.isEmpty {
                Section("Rejected") {
                    ForEach(snapshot.rejected, id: \.self) { r in
                        Label(r, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red, .primary)
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
            Section {
                Button {
                    UIPasteboard.general.string = snapshot.contextText()
                    showCopied = true
                } label: {
                    Label("Copy context", systemImage: "doc.on.clipboard")
                }
            }
        }
        .navigationTitle(snapshot.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showCopied {
                Text("Copied ✓")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
        .animation(.easeInOut(duration: 0.25), value: showCopied)
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
                    NavigationLink(destination: PromptDetailView(prompt: p, onSave: { updated in
                        SharedStorage.shared.addPrompt(updated)
                        prompts = SharedStorage.shared.prompts
                    })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title).font(.headline)
                            Text(p.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if !p.variables.isEmpty {
                                Text(p.variables.map { "{{\($0)}}" }.joined(separator: " "))
                                    .font(.caption)
                                    .foregroundStyle(.accentColor)
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
            NavigationStack {
                Form {
                    Section("Title") { TextField("", text: $newTitle) }
                    Section("Body") { TextEditor(text: $newBody).frame(minHeight: 100) }
                }
                .navigationTitle("New Prompt")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showNew = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard !newTitle.isEmpty, !newBody.isEmpty else { return }
                            SharedStorage.shared.addPrompt(PromptItem(
                                title: String(newTitle.prefix(100)),
                                body: String(newBody.prefix(2000))
                            ))
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
}

struct PromptDetailView: View {
    @State var prompt: PromptItem
    let onSave: (PromptItem) -> Void
    @State private var varValues: [String: String] = [:]
    @State private var showCopied = false
    @Environment(\.dismiss) private var dismiss

    var resolved: String { prompt.resolved(with: varValues) }

    var body: some View {
        List {
            Section("Body") { Text(prompt.body) }
            if !prompt.variables.isEmpty {
                Section("Variables") {
                    ForEach(prompt.variables, id: \.self) { v in
                        HStack {
                            Text("{{\(v)}}").foregroundStyle(.accentColor).font(.caption.monospaced())
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
                    Text(resolved).font(.body).foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    UIPasteboard.general.string = resolved
                    showCopied = true
                } label: {
                    Label("Copy", systemImage: "doc.on.clipboard")
                }
            }
        }
        .navigationTitle(prompt.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showCopied {
                Text("Copied ✓")
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showCopied = false }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCopied)
    }
}

// MARK: - Files Tab

struct FilesTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Files",
                systemImage: "doc.on.doc",
                description: Text("Drag & drop files from the browser extension will appear here.\nFile sync via Google Drive coming soon.")
            )
            .navigationTitle("Files")
        }
    }
}

// MARK: - Mind Map Tab

struct MindMapTab: View {
    @State private var snapshots = SharedStorage.shared.snapshots

    var body: some View {
        NavigationStack {
            if snapshots.isEmpty {
                ContentUnavailableView(
                    "No snapshots",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Save snapshots to see the context graph")
                )
            } else {
                MindMapView(snapshots: snapshots)
            }
        }
        .onAppear { snapshots = SharedStorage.shared.snapshots }
        .navigationTitle("Mind Map")
    }
}

struct MindMapView: View {
    let snapshots: [Snapshot]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                // Draw edges
                ForEach(snapshots) { snap in
                    if let parentId = snap.parentId,
                       let parent = snapshots.first(where: { $0.id == parentId }) {
                        let from = nodePos(for: parent, in: snapshots)
                        let to   = nodePos(for: snap,   in: snapshots)
                        Path { p in
                            p.move(to: from)
                            p.addLine(to: to)
                        }
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    }
                }
                // Draw nodes
                ForEach(Array(snapshots.enumerated()), id: \.element.id) { i, snap in
                    let pos = nodePos(for: snap, in: snapshots)
                    VStack(spacing: 4) {
                        Circle()
                            .fill(llmColor(snap.llmSource))
                            .frame(width: 12, height: 12)
                        Text(snap.title)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(width: 80)
                            .multilineTextAlignment(.center)
                    }
                    .position(pos)
                }
            }
            .frame(width: 600, height: 400)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func nodePos(for snap: Snapshot, in list: [Snapshot]) -> CGPoint {
        guard let i = list.firstIndex(of: snap) else { return .zero }
        let cols: CGFloat = 4
        let col = CGFloat(i % Int(cols))
        let row = CGFloat(i / Int(cols))
        return CGPoint(x: 80 + col * 130, y: 60 + row * 100)
    }

    private func llmColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "claude": return .orange
        case "chatgpt": return .green
        case "gemini": return .blue
        default: return .accentColor
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
                        Text("Reads your existing SessionPort backups. Scope: drive.file only.")
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
                    Link(destination: URL(string: "https://github.com/Den1style/sessionport")!) {
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

// MARK: - Shared UI components

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
            Text(snapshot.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.system(size: 11)).foregroundStyle(.tertiary)
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
