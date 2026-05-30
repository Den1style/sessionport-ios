import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

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

// MARK: - Tab structure

struct MainTabView: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService

    var body: some View {
        TabView {
            SnapshotsTab()
                .tabItem { Label("История", systemImage: "clock.arrow.circlepath") }
                .environmentObject(drive)
                .environmentObject(store)

            PromptsLibraryTab()
                .tabItem { Label("Промпты", systemImage: "pencil.and.list.clipboard") }

            MindMapContainerView()
                .tabItem { Label("Mind Map", systemImage: "brain.head.profile") }

            SettingsTab()
                .tabItem { Label("Настройки", systemImage: "gear") }
                .environmentObject(drive)
                .environmentObject(store)
        }
    }
}

// MARK: - Snapshots Tab (История)

struct SnapshotsTab: View {
    @EnvironmentObject var drive: GoogleDriveService
    @EnvironmentObject var store: StoreKitService

    @State private var snapshots = SharedStorage.shared.activeSnapshots
    @State private var search = ""
    @State private var selectedProject: String? = nil
    @State private var showPaywall = false
    @State private var showTrash = false
    @State private var showExport = false
    @State private var showImport = false
    @State private var importError: String? = nil

    private var freeRemaining: Int { max(0, 5 - snapshots.count) }
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
                            ProjectChip(label: "Все", isActive: selectedProject == nil) {
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
                        search.isEmpty ? "Нет снэпшотов" : "Ничего не найдено",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(search.isEmpty
                            ? "Используй клавиатуру SessionPort для захвата контекста"
                            : "Попробуй другой запрос")
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
            .searchable(text: $search, prompt: "Поиск снэпшотов")
            .navigationTitle("История")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button { showExport = true } label: {
                            Label("Экспорт JSON", systemImage: "square.and.arrow.up")
                        }
                        Button { showImport = true } label: {
                            Label("Импорт JSON", systemImage: "square.and.arrow.down")
                        }
                        Divider()
                        Button {
                            showTrash = true
                        } label: {
                            Label("Корзина (\(trashCount))", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                if drive.isConnected {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { Task { await drive.sync() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .symbolEffect(.rotate, isActive: drive.isSyncing)
                        }
                    }
                }
            }
            .refreshable {
                if drive.isConnected { await drive.sync() }
                snapshots = SharedStorage.shared.activeSnapshots
            }
            .onAppear { snapshots = SharedStorage.shared.activeSnapshots }
            .sheet(isPresented: $showTrash) { TrashView() }
            .sheet(isPresented: $showPaywall) { PaywallView(reason: "Нужно больше снэпшотов") }
            .sheet(isPresented: $showExport) { ExportView() }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alert("Ошибка импорта", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK") { importError = nil }
            } message: { Text(importError ?? "") }
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

    private func exportSelected() {
        let toExport = selected.isEmpty ? snapshots : snapshots.filter { selected.contains($0.id) }
        let payload: [String: Any] = [
            "schema_version": 1,
            "snapshots": toExport.map { snap -> [String: Any] in
                ["transfer_id": snap.id, "title": snap.title,
                 "llm_source": snap.llmSource, "project": snap.project ?? ""]
            }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessionport-export-\(Int(Date().timeIntervalSince1970)).json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController?
            .present(av, animated: true)
        dismiss()
    }
}

// MARK: - Storage Bar

struct StorageBar: View {
    let count: Int
    private let max = 200

    var body: some View {
        HStack(spacing: 8) {
            Text("Буфер:")
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
    @State private var prompts = SharedStorage.shared.prompts
    @State private var showNew = false
    @State private var search = ""

    private var filtered: [PromptItem] {
        search.isEmpty ? prompts : prompts.filter {
            $0.title.localizedCaseInsensitiveContains(search)
            || $0.body.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { p in
                    NavigationLink(destination: PromptDetailView(prompt: p)) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                if p.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.caption).foregroundStyle(.yellow)
                                }
                                Text(p.title).font(.headline)
                            }
                            Text(p.body)
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            HStack(spacing: 8) {
                                if !p.variables.isEmpty {
                                    Text(p.variables.map { "{{\($0)}}" }.joined(separator: " "))
                                        .font(.caption).foregroundStyle(.accentColor)
                                }
                                if !p.attachedFiles.isEmpty {
                                    Text("📎 \(p.attachedFiles.count)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete { idx in
                    idx.forEach { SharedStorage.shared.deletePrompt(id: filtered[$0].id) }
                    prompts = SharedStorage.shared.prompts
                }
            }
            .searchable(text: $search, prompt: "Поиск промптов")
            .navigationTitle("Промпты")
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
                Section("Название") {
                    TextField("Название промпта", text: $title)
                }
                Section("Текст (используй {{переменная}} для плейсхолдеров)") {
                    TextEditor(text: $body_).frame(minHeight: 100)
                }
                Section {
                    Toggle("Избранное", isOn: $isFavorite)
                }
            }
            .navigationTitle("Новый промпт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard !title.isEmpty, !body_.isEmpty else { return }
                        onSave(PromptItem(title: String(title.prefix(100)),
                                         body: String(body_.prefix(2000)),
                                         isFavorite: isFavorite))
                        dismiss()
                    }
                    .disabled(title.isEmpty || body_.isEmpty)
                }
            }
        }
    }
}

// MARK: - Prompt Detail View

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
            Section("Текст") { Text(prompt.body) }

            if !prompt.variables.isEmpty {
                Section("Переменные") {
                    ForEach(prompt.variables, id: \.self) { v in
                        HStack {
                            Text("{{\(v)}}").foregroundStyle(.accentColor).font(.caption.monospaced())
                            Spacer()
                            TextField("значение", text: Binding(
                                get: { varValues[v] ?? "" },
                                set: { varValues[v] = $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }
                Section("Предпросмотр") {
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
                            prompt.attachedFiles.removeAll { $0.id == file.id }
                            SharedStorage.shared.updatePrompt(prompt)
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(.red)
                    }
                }
                Button { showFilePicker = true } label: {
                    Label("Прикрепить файл", systemImage: "paperclip").foregroundStyle(.accentColor)
                }
            } header: {
                HStack {
                    Text("Файлы")
                    if !prompt.attachedFiles.isEmpty {
                        Text("(\(prompt.attachedFiles.count))").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = resolved
                    showCopied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { showCopied = false } }
                } label: {
                    Label(showCopied ? "Скопировано ✓" : "Скопировать и вставить",
                          systemImage: "doc.on.clipboard")
                }
                Toggle("Избранное", isOn: Binding(
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
        .alert("Ошибка файла", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
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
                    fileError = "\(url.lastPathComponent) превышает лимит 5 МБ"; continue
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
    @State private var connectError: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Подписка") {
                    if store.isPro {
                        Label("SessionPort Pro — Активна", systemImage: "crown.fill")
                            .foregroundStyle(.yellow)
                    } else {
                        Button { showPaywall = true } label: {
                            HStack {
                                Label("Перейти на Pro", systemImage: "crown")
                                Spacer()
                                Text("$4.99/мес").foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    Button("Восстановить покупки") { Task { await store.restorePurchases() } }
                        .foregroundStyle(.accentColor)
                }

                Section("Google Drive") {
                    if drive.isConnected {
                        Label(drive.email ?? "Подключено", systemImage: "checkmark.icloud.fill")
                            .foregroundStyle(.green)
                        if let last = drive.lastSync {
                            HStack {
                                Text("Последняя синхронизация")
                                Spacer()
                                Text(last, style: .relative).foregroundStyle(.secondary)
                            }
                        }
                        Button { Task { await drive.sync() } } label: {
                            HStack {
                                Label("Синхронизировать", systemImage: "arrow.clockwise")
                                if drive.isSyncing { Spacer(); ProgressView().scaleEffect(0.8) }
                            }
                        }
                        .disabled(drive.isSyncing)
                        Button(role: .destructive) { drive.disconnect() } label: {
                            Label("Отключить", systemImage: "xmark.icloud")
                        }
                    } else {
                        Button {
                            Task {
                                do { try await drive.connect() }
                                catch { connectError = error.localizedDescription }
                            }
                        } label: {
                            Label("Подключить Google Drive", systemImage: "icloud.and.arrow.up")
                        }
                        Text("Читает резервные копии SessionPort. Только ваши файлы.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("О приложении") {
                    HStack {
                        Text("Версия")
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
            .navigationTitle("Настройки")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(reason: "Разблокируй безлимитные снэпшоты и синхронизацию")
        }
        .alert("Ошибка Google Drive", isPresented: Binding(
            get: { connectError != nil },
            set: { if !$0 { connectError = nil } }
        )) {
            Button("OK") { connectError = nil }
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

struct FreemiumBanner: View {
    let remaining: Int
    let onUpgrade: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Осталось \(remaining) снэпшот\(remaining == 1 ? "" : "а")")
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
                    Text(proj).font(.system(size: 10)).foregroundStyle(.accentColor)
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
