import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService
    @EnvironmentObject var settings: AppSettings
    @AppStorage("sp_onboarding_done") private var onboardingDone = false

    var body: some View {
        Group {
            if !onboardingDone {
                OnboardingView(onDone: { onboardingDone = true })
            } else {
                MainTabView()
                    .environmentObject(drive)
                    .environmentObject(store)
                    .environmentObject(settings)
            }
        }
        // Re-render whole tree when language changes
        .id(settings.language)
    }
}

// MARK: - Tab structure

struct MainTabView: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            SnapshotsTab()
                .tabItem { Label(L.t("tab.history"), systemImage: "clock.arrow.circlepath") }
                .environmentObject(drive)
                .environmentObject(store)

            PromptsLibraryTab()
                .tabItem { Label(L.t("tab.prompts"), systemImage: "pencil.and.list.clipboard") }

            MindMapContainerView()
                .tabItem { Label(L.t("tab.mindmap"), systemImage: "brain.head.profile") }

            SettingsTab()
                .tabItem { Label(L.t("tab.settings"), systemImage: "gear") }
                .environmentObject(drive)
                .environmentObject(store)
                .environmentObject(settings)
        }
    }
}

// MARK: - Snapshots Tab (История)

struct SnapshotsTab: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService
    @AppStorage("sp_keyboard_setup_done") private var keyboardSetupDone = false

    @State private var snapshots = SharedStorage.shared.activeSnapshots
    @State private var search = ""
    @State private var selectedProject: String? = nil
    @State private var showPaywall = false
    @State private var showTrash = false
    @State private var showExport = false
    @State private var showImport = false
    @State private var importError: String? = nil
    @State private var showRename = false
    @State private var renameText = ""

    // Limit counts device-captured snapshots only (synced/imported are free) —
    // must match SharedStorage.canAddSnapshot.
    private var freeRemaining: Int { SharedStorage.shared.freeSnapshotsRemaining }
    private var projects: [String] { SharedStorage.shared.allProjects }
    private var trashCount: Int { SharedStorage.shared.trashedSnapshots.count }

    private var filtered: [Snapshot] {
        var list = snapshots
        if let proj = selectedProject { list = list.filter { $0.project == proj } }
        if !search.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(search)
                || $0.goal.localizedCaseInsensitiveContains(search)
                || ($0.project ?? "").localizedCaseInsensitiveContains(search)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                // Keyboard setup banner
                if !keyboardSetupDone {
                    KeyboardSetupBanner { keyboardSetupDone = true }
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }

                // Sync banner
                if drive.isConnected {
                    SyncBanner(drive: drive)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }

                // Freemium banner
                if !store.isPro && snapshots.count > 0 {
                    FreemiumBanner(remaining: freeRemaining) { showPaywall = true }
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }

                // Project filter chips
                if !projects.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ProjectChip(label: L.t("snap.all"), isActive: selectedProject == nil) {
                                selectedProject = nil
                            }
                            ForEach(projects, id: \.self) { proj in
                                ProjectChip(label: proj, isActive: selectedProject == proj) {
                                    selectedProject = selectedProject == proj ? nil : proj
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                // Storage bar
                StorageBar(count: snapshots.count)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 2, leading: 16, bottom: 2, trailing: 16))

                // Snapshot list
                if filtered.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? L.t("snap.empty.title") : L.t("snap.notfound"),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(search.isEmpty
                            ? L.t("snap.empty.desc")
                            : L.t("snap.notfound.desc"))
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { snap in
                        NavigationLink(destination: SnapshotDetailView(snapshot: snap)) {
                            SnapshotListRow(snapshot: snap)
                        }
                    }
                    .onDelete { idx in
                        idx.forEach {
                            SharedStorage.shared.moveToTrash(id: filtered[$0].id)
                        }
                        snapshots = SharedStorage.shared.activeSnapshots
                    }
                }
            }
            .searchable(text: $search, prompt: L.t("snap.search"))
            .navigationTitle(L.t("snap.title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button { showExport = true } label: {
                            Label(L.t("snap.export"), systemImage: "square.and.arrow.up")
                        }
                        Button { showImport = true } label: {
                            Label(L.t("snap.import"), systemImage: "square.and.arrow.down")
                        }
                        if let proj = selectedProject {
                            Button {
                                renameText = proj
                                showRename = true
                            } label: {
                                Label("\(L.t("proj.rename")) «\(proj)»", systemImage: "pencil")
                            }
                        }
                        Divider()
                        Button {
                            showTrash = true
                        } label: {
                            Label("\(L.t("trash.title")) (\(trashCount))", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                if drive.isConnected {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { Task { await drive.sync() } } label: {
                            Image(systemName: drive.isSyncing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                if drive.isConnected { await drive.sync() }
                snapshots = SharedStorage.shared.activeSnapshots
            }
            .onAppear {
                snapshots = SharedStorage.shared.activeSnapshots
                // Extension parity: autosync on open, throttled to 1/min inside.
                Task {
                    await drive.autoSyncIfNeeded()
                    snapshots = SharedStorage.shared.activeSnapshots
                }
            }
            .sheet(isPresented: $showTrash) { TrashView() }
            .sheet(isPresented: $showPaywall) { PaywallView(reason: "Нужно больше снэпшотов") }
            .sheet(isPresented: $showExport) { ExportView() }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alert(L.t("snap.importError"), isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button(L.t("common.ok")) { importError = nil }
            } message: { Text(importError ?? "") }
            .alert(L.t("proj.rename"), isPresented: $showRename) {
                TextField(L.t("proj.name"), text: $renameText)
                Button(L.t("common.save")) {
                    if let old = selectedProject {
                        SharedStorage.shared.renameProject(old, to: renameText)
                        selectedProject = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        snapshots = SharedStorage.shared.activeSnapshots
                    }
                }
                Button(L.t("common.cancel"), role: .cancel) {}
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e): importError = e.localizedDescription
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Нет доступа к файлу"; return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                importError = "Не удалось прочитать файл"; return
            }
            let imported = Snapshot.fromBackupJSON(data)
            guard !imported.isEmpty else {
                importError = "Файл не содержит снэпшотов SessionPort"; return
            }
            imported.forEach { SharedStorage.shared.addSnapshot($0) }
            snapshots = SharedStorage.shared.activeSnapshots
        }
    }
}

// MARK: - Export View

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    private let snapshots = SharedStorage.shared.activeSnapshots

    var body: some View {
        NavigationStack {
            List(snapshots, selection: $selected) { snap in
                VStack(alignment: .leading, spacing: 3) {
                    Text(snap.title).font(.headline)
                    Text(snap.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Экспорт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Экспорт (\(selected.isEmpty ? snapshots.count : selected.count))") {
                        exportSelected()
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    private func topMostViewController(_ vc: UIViewController) -> UIViewController {
        vc.presentedViewController.map { topMostViewController($0) } ?? vc
    }

    private func exportSelected() {
        let toExport = selected.isEmpty ? snapshots : snapshots.filter { selected.contains($0.id) }
        // Browser-compatible format (schema_version 1) — unified iOS ⇄ extension
        let data = SnapshotInterchange.exportJSON(toExport)
        guard !data.isEmpty else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessionport-backup-\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: url)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // Use topMostViewController so sheet/modal stacks are handled correctly.
        // Dismiss only AFTER sharing finishes — dismissing the presenting sheet
        // immediately would tear the share sheet down with it.
        av.completionWithItemsHandler = { _, completed, _, _ in
            // Secure deletion of temp export file after sharing completes
            try? FileManager.default.removeItem(at: url)
            if completed { dismiss() }
        }
        if let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController {
            topMostViewController(root).present(av, animated: true)
        }
    }
}

// MARK: - Storage Bar

struct StorageBar: View {
    let count: Int
    private let max = 200

    var body: some View {
        HStack(spacing: 8) {
            Text(L.t("snap.buffer"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: geo.size.width * CGFloat(count) / CGFloat(max))
                }
            }
            .frame(height: 4)
            Text("\(count) / \(max)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var fillColor: Color {
        let ratio = Double(count) / Double(max)
        if ratio > 0.8 { return .red }
        if ratio > 0.6 { return .orange }
        return .green
    }
}

// MARK: - Prompts Library Tab

struct PromptsLibraryTab: View {
    @State private var prompts = SharedStorage.shared.activePrompts
    @State private var showNew = false
    @State private var showTrash = false
    @State private var search = ""
    @State private var pendingDelete: PromptItem? = nil
    @State private var showImport = false
    @State private var importError: String? = nil

    private var trashCount: Int { SharedStorage.shared.trashedPrompts.count }

    private var filtered: [PromptItem] {
        search.isEmpty ? prompts : prompts.filter {
            $0.title.localizedCaseInsensitiveContains(search)
            || $0.body.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        L.t("prompts.empty"),
                        systemImage: "pencil.and.list.clipboard"
                    )
                } else {
                    List {
                        ForEach(filtered) { p in
                            NavigationLink(destination: PromptDetailView(prompt: p) {
                                prompts = SharedStorage.shared.activePrompts
                            }) {
                                promptRow(p)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { pendingDelete = p } label: {
                                    Label(L.t("common.delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: L.t("prompts.search"))
            .navigationTitle(L.t("prompts.title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button { exportPrompts() } label: {
                            Label(L.t("snap.export"), systemImage: "square.and.arrow.up")
                        }
                        Button { showImport = true } label: {
                            Label(L.t("snap.import"), systemImage: "square.and.arrow.down")
                        }
                        Divider()
                        Button { showTrash = true } label: {
                            Label("\(L.t("prompts.trash")) (\(trashCount))", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
                handlePromptImport(result)
            }
            .alert(L.t("snap.importError"), isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button(L.t("common.ok")) { importError = nil }
            } message: { Text(importError ?? "") }
            .onAppear { prompts = SharedStorage.shared.activePrompts }
        }
        .sheet(isPresented: $showNew) {
            NewPromptSheet { prompt in
                SharedStorage.shared.addPrompt(prompt)
                prompts = SharedStorage.shared.activePrompts
            }
        }
        .sheet(isPresented: $showTrash, onDismiss: {
            prompts = SharedStorage.shared.activePrompts
        }) {
            PromptTrashView()
        }
        .confirmationDialog(
            L.t("prompt.delete.title"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { p in
            Button(L.t("common.delete"), role: .destructive) {
                SharedStorage.shared.movePromptToTrash(id: p.id)
                prompts = SharedStorage.shared.activePrompts
            }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: { _ in
            Text(L.t("prompt.delete.msg"))
        }
    }

    // MARK: Export / Import (browser-compatible sessionport_prompts_v1)

    private func exportPrompts() {
        let data = PromptInterchange.exportJSON(
            active: SharedStorage.shared.activePrompts,
            trashed: SharedStorage.shared.trashedPrompts
        )
        guard !data.isEmpty else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessionport-prompts-\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: url)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        av.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url) }
        if let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(av, animated: true)
        }
    }

    private func handlePromptImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e): importError = e.localizedDescription
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Нет доступа к файлу"; return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                importError = "Не удалось прочитать файл"; return
            }
            let items = PromptInterchange.parse(data)
            guard !items.isEmpty else {
                importError = "Файл не содержит промптов SessionPort"; return
            }
            SharedStorage.shared.importPrompts(items)
            prompts = SharedStorage.shared.activePrompts
        }
    }

    @ViewBuilder
    private func promptRow(_ p: PromptItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if p.isFavorite {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                }
                Text(p.title).font(.headline)
            }
            Text(p.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 8) {
                if !p.variables.isEmpty {
                    Text(p.variables.map { "{{\($0)}}" }.joined(separator: " "))
                        .font(.caption).foregroundStyle(Color.accentColor)
                }
                if !p.attachedFiles.isEmpty {
                    Text("📎 \(p.attachedFiles.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - New Prompt Sheet

struct NewPromptSheet: View {
    let onSave: (PromptItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var isFavorite = false
    @State private var files: [AttachedFile] = []
    @State private var showFilePicker = false
    @State private var fileError: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section(L.t("prompt.new.name")) {
                    TextField(L.t("prompt.new.nameField"), text: $title)
                }
                Section(L.t("prompt.new.bodyHeader")) {
                    TextEditor(text: $body_).frame(minHeight: 100)
                }
                Section {
                    ForEach(files) { file in
                        HStack(spacing: 10) {
                            FileIcon(mimeType: file.mimeType)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(file.displaySize).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                files.removeAll { $0.id == file.id }
                            } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.plain).foregroundStyle(.red)
                        }
                    }
                    Button { showFilePicker = true } label: {
                        Label(L.t("prompt.attach"), systemImage: "paperclip")
                            .foregroundStyle(Color.accentColor)
                    }
                } header: {
                    Text(L.t("prompt.files"))
                }
                Section {
                    Toggle(L.t("prompt.favorite"), isOn: $isFavorite)
                }
            }
            .navigationTitle(L.t("prompt.new.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.save")) {
                        guard !title.isEmpty, !body_.isEmpty else { return }
                        onSave(PromptItem(title: String(title.prefix(100)),
                                         body: String(body_.prefix(2000)),
                                         attachedFiles: files,
                                         isFavorite: isFavorite))
                        dismiss()
                    }
                    .disabled(title.isEmpty || body_.isEmpty)
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                handleFilePick(result)
            }
            .alert(L.t("prompt.fileError"), isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
                Button(L.t("common.ok")) { fileError = nil }
            } message: { Text(fileError ?? "") }
        }
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
                    fileError = "\(url.lastPathComponent) \(L.t("prompt.fileLimit"))"; continue
                }
                files.append(AttachedFile(
                    id: UUID().uuidString,
                    name: url.lastPathComponent,
                    mimeType: url.mimeType,
                    sizeBytes: data.count,
                    base64: data.base64EncodedString()
                ))
            }
        }
    }
}

// MARK: - Prompt Detail View

struct PromptDetailView: View {
    @State var prompt: PromptItem
    var onChange: () -> Void = {}
    @State private var varValues: [String: String] = [:]
    @State private var showCopied = false
    @State private var showFilePicker = false
    @State private var fileError: String? = nil
    @State private var pendingFileDelete: AttachedFile? = nil
    @Environment(\.dismiss) private var dismiss

    var resolved: String { prompt.insertionText(variableValues: varValues) }

    var body: some View {
        List {
            Section(L.t("prompt.text")) { Text(prompt.body) }

            if !prompt.variables.isEmpty {
                Section(L.t("prompt.variables")) {
                    ForEach(prompt.variables, id: \.self) { v in
                        HStack {
                            Text("{{\(v)}}").foregroundStyle(Color.accentColor).font(.caption.monospaced())
                            Spacer()
                            TextField(L.t("prompt.value"), text: Binding(
                                get: { varValues[v] ?? "" },
                                set: { varValues[v] = $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }
                Section(L.t("prompt.preview")) {
                    Text(resolved).font(.body).foregroundStyle(.secondary)
                }
            }

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
                            pendingFileDelete = file
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(.red)
                    }
                }
                Button { showFilePicker = true } label: {
                    Label(L.t("prompt.attach"), systemImage: "paperclip").foregroundStyle(Color.accentColor)
                }
            } header: {
                HStack {
                    Text(L.t("prompt.files"))
                    if !prompt.attachedFiles.isEmpty {
                        Text("(\(prompt.attachedFiles.count))").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    copyWithExpiration(resolved)
                    showCopied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { showCopied = false } }
                } label: {
                    Label(showCopied ? L.t("prompt.copied") : L.t("prompt.copy"),
                          systemImage: "doc.on.clipboard")
                }
                Toggle(L.t("prompt.favorite"), isOn: Binding(
                    get: { prompt.isFavorite },
                    set: { prompt.isFavorite = $0; SharedStorage.shared.updatePrompt(prompt); onChange() }
                ))
            }
        }
        .navigationTitle(prompt.title)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            handleFilePick(result)
        }
        .alert(L.t("prompt.fileError"), isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button(L.t("common.ok")) { fileError = nil }
        } message: { Text(fileError ?? "") }
        .confirmationDialog(
            L.t("file.delete.title"),
            isPresented: Binding(get: { pendingFileDelete != nil }, set: { if !$0 { pendingFileDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingFileDelete
        ) { file in
            Button(L.t("common.delete"), role: .destructive) {
                prompt.attachedFiles.removeAll { $0.id == file.id }
                SharedStorage.shared.updatePrompt(prompt)
                onChange()
            }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: { _ in Text(L.t("file.delete.msg")) }
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
                    fileError = "\(url.lastPathComponent) \(L.t("prompt.fileLimit"))"; continue
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
            onChange()
        }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService
    @EnvironmentObject var settings: AppSettings
    @State private var showPaywall = false
    @State private var connectError: String? = nil
    @State private var showKeyboardHelp = false

    private func themeLabel(_ t: AppTheme) -> String {
        switch t {
        case .system: return L.t("settings.theme.system")
        case .light:  return L.t("settings.theme.light")
        case .dark:   return L.t("settings.theme.dark")
        }
    }
    private func langLabel(_ l: AppLanguage) -> String {
        switch l {
        case .system: return L.t("settings.language.system")
        case .en:     return "English"
        case .ru:     return "Русский"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L.t("settings.appearance")) {
                    Picker(L.t("settings.theme"), selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { Text(themeLabel($0)).tag($0) }
                    }
                    Picker(L.t("settings.language"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text(langLabel($0)).tag($0) }
                    }
                }

                Section(L.t("settings.keyboard")) {
                    Button { showKeyboardHelp = true } label: {
                        Label(L.t("settings.keyboard.howto"), systemImage: "keyboard")
                    }
                }

                Section(L.t("settings.subscription")) {
                    if store.isPro {
                        Label(L.t("settings.pro.active"), systemImage: "crown.fill")
                            .foregroundStyle(.yellow)
                    } else {
                        Button { showPaywall = true } label: {
                            HStack {
                                Label(L.t("settings.pro.upgrade"), systemImage: "crown")
                                Spacer()
                                Text("$4.99/mo").foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    Button(L.t("settings.restore")) { Task { await store.restorePurchases() } }
                        .foregroundStyle(Color.accentColor)
                }

                Section(L.t("settings.gdrive")) {
                    if drive.isConnected {
                        Label(drive.email ?? L.t("settings.connected"), systemImage: "checkmark.icloud.fill")
                            .foregroundStyle(.green)
                        if let last = drive.lastSync {
                            HStack {
                                Text(L.t("settings.lastSync"))
                                Spacer()
                                Text(last, style: .relative).foregroundStyle(.secondary)
                            }
                        }
                        Button { Task { await drive.backup() } } label: {
                            HStack {
                                Label(L.t("settings.backup"), systemImage: "icloud.and.arrow.up")
                                if drive.isSyncing { Spacer(); ProgressView().scaleEffect(0.8) }
                            }
                        }
                        .disabled(drive.isSyncing)
                        Button { Task { await drive.sync() } } label: {
                            HStack {
                                Label(L.t("settings.restoreDrive"), systemImage: "arrow.triangle.2.circlepath.icloud")
                                if drive.isSyncing { Spacer(); ProgressView().scaleEffect(0.8) }
                            }
                        }
                        .disabled(drive.isSyncing)
                        Button(role: .destructive) { drive.disconnect() } label: {
                            Label(L.t("settings.disconnect"), systemImage: "xmark.icloud")
                        }
                    } else {
                        Button {
                            Task {
                                do { try await drive.connect() }
                                catch { connectError = error.localizedDescription }
                            }
                        } label: {
                            Label(L.t("settings.connectDrive"), systemImage: "icloud.and.arrow.up")
                        }
                        Text(L.t("settings.drive.note"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(L.t("settings.about")) {
                    HStack {
                        Text(L.t("settings.version"))
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
                    Link(destination: URL(string: "https://twitter.com/SessionPort")!) {
                        Label("Twitter / X", systemImage: "bird")
                    }
                }
            }
            .navigationTitle(L.t("settings.title"))
        }
        .sheet(isPresented: $showKeyboardHelp) {
            KeyboardSetupSheet(onDone: { showKeyboardHelp = false })
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: L.t("settings.pro.upgrade"))
        }
        .alert(L.t("settings.drive.error"), isPresented: Binding(
            get: { connectError != nil },
            set: { if !$0 { connectError = nil } }
        )) {
            Button(L.t("common.ok")) { connectError = nil }
        } message: { Text(connectError ?? "") }
    }
}

// MARK: - Shared UI Components

struct SyncBanner: View {
    @ObservedObject var drive: GoogleDriveService
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.icloud").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(drive.email ?? "Подключено").font(.system(size: 13, weight: .medium))
                if let last = drive.lastSync {
                    Text("Синхронизировано \(last, style: .relative) назад")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
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

struct KeyboardSetupBanner: View {
    let onDone: () -> Void
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("kb.banner.title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(L.t("kb.banner.sub"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 4)
        .sheet(isPresented: $showSheet) {
            KeyboardSetupSheet(onDone: {
                showSheet = false
                withAnimation { onDone() }
            })
        }
    }
}

struct KeyboardSetupSheet: View {
    let onDone: () -> Void

    private var steps: [(icon: String, title: String, body: String)] {
        [
            ("gear",        L.t("kb.step1.title"), L.t("kb.step1.body")),
            ("plus.circle", L.t("kb.step2.title"), L.t("kb.step2.body")),
            ("hand.tap",    L.t("kb.step3.title"), L.t("kb.step3.body")),
            ("globe",       L.t("kb.step4.title"), L.t("kb.step4.body")),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Text("\(index + 1)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.system(size: 15, weight: .semibold))
                            Text(step.body)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(.init(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                Section {
                    Button {
                        let url = URL(string: "App-prefs:General&path=Keyboard/KEYBOARDS")
                            ?? URL(string: UIApplication.openSettingsURLString)!
                        UIApplication.shared.open(url)
                    } label: {
                        HStack {
                            Spacer()
                            Label(L.t("kb.openKbSettings"), systemImage: "arrow.up.right.square")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.accentColor)
                }
            }
            .navigationTitle(L.t("kb.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.done")) { onDone() }
                }
            }
        }
    }
}

struct FreemiumBanner: View {
    let remaining: Int
    let onUpgrade: () -> Void

    // Russian plural: 1 снэпшот · 2–4 снэпшота · 0/5+ снэпшотов
    private var noun: String {
        let mod100 = remaining % 100, mod10 = remaining % 10
        if (11...14).contains(mod100) { return "снэпшотов" }
        switch mod10 {
        case 1:      return "снэпшот"
        case 2...4:  return "снэпшота"
        default:     return "снэпшотов"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Осталось \(remaining) \(noun)")
                    .font(.system(size: 13, weight: .medium))
                Text("Перейди на Pro для безлимита").font(.system(size: 11)).foregroundStyle(.secondary)
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
                if let proj = snapshot.project {
                    Text(proj).font(.system(size: 10)).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
                Text(snapshot.llmSource.capitalized)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            if !snapshot.goal.isEmpty {
                Text(snapshot.goal).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(snapshot.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                if !snapshot.attachedFiles.isEmpty {
                    Text("📎 \(snapshot.attachedFiles.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func llmColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "claude": return .orange; case "chatgpt": return .green
        case "gemini": return .blue; case "grok": return .primary
        case "perplexity": return .purple; default: return .gray
        }
    }
}
