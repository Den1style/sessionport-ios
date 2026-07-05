import SwiftUI

// Panel height — compact like a utility keyboard, no large dead zone at the
// bottom. Matched against the system default via predictive offset in the VC.
// 235 = header(46) + dividers + project bar(39) + extended grid worst case —
// content fills the panel edge-to-edge, no empty band above the home indicator.
let kbExpandedHeight: CGFloat = 235

enum KeyboardTab: Equatable { case transfer, prompts }
enum PanelScreen: Equatable { case main, history }

struct KeyboardPanelView: View {
    let llmName: String
    let onInsertText: (String) -> Void
    let onClear: () -> Void

    @State private var activeTab: KeyboardTab
    @State private var screen: PanelScreen = .main
    @State private var flowState: TransferFlowState
    @State private var project: String          // "" == new project
    @State private var projects: [String]

    init(llmName: String,
         onInsertText: @escaping (String) -> Void,
         onClear: @escaping () -> Void) {
        self.llmName = llmName
        self.onInsertText = onInsertText
        self.onClear = onClear
        _activeTab = State(initialValue: SharedStorage.shared.kbTab == "prompts" ? .prompts : .transfer)
        _flowState = State(initialValue: TransferFlowState.restored())
        let projs = SharedStorage.shared.allProjects
        _projects = State(initialValue: projs)
        // Default selection: keep a valid saved choice (incl. "new"), else fall
        // back to the most recent snapshot's project, else "new".
        let saved = SharedStorage.shared.kbProject
        let initial: String
        if saved == "__new__" || projs.contains(saved) {
            initial = saved
        } else {
            initial = SharedStorage.shared.activeSnapshots.first?.project ?? "__new__"
        }
        _project = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            if screen == .main && activeTab == .transfer {
                projectBar
                Divider().overlay(Color.white.opacity(0.06))
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .onAppear { refreshProjects() }
        .onChange(of: flowState) { _, newValue in
            newValue.persist()
            // A completed transfer may have created a new project — refresh chips
            refreshProjects()
        }
        .onChange(of: activeTab) { _, newValue in
            SharedStorage.shared.kbTab = (newValue == .prompts) ? "prompts" : "transfer"
        }
        .onChange(of: project) { _, newValue in
            SharedStorage.shared.kbProject = newValue
        }
    }

    // Reload the chip list and make sure the current selection is still valid —
    // a stale selection would leave every chip (incl. "＋ New") unhighlighted.
    private func refreshProjects() {
        projects = SharedStorage.shared.allProjects
        if project != "__new__" && !projects.contains(project) {
            project = projects.first ?? "__new__"
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    screen = screen == .history ? .main : .history
                    if screen == .main { flowState = .modeSelection }
                }
            } label: {
                ZStack {
                    Circle().fill(Color(red: 0.44, green: 0.33, blue: 0.85))
                        .frame(width: 32, height: 32)
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            if screen == .main {
                HStack(spacing: 3) {
                    tabPill(label: "—— Transfer", tab: .transfer, activeColor: Color(red: 0.85, green: 0.55, blue: 0.1))
                    tabPill(label: "✏️ Prompts", tab: .prompts, activeColor: Color(red: 0.44, green: 0.33, blue: 0.85))
                }
            } else {
                Text(L.t("kb.history.header"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }

            Spacer()

            // Clear — wipes the text field in the host app
            Button(action: onClear) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12, weight: .semibold))
                    Text("Clear").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: Project bar — pick the target project (avoids project mix-ups)

    private var projectBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                projectChip(title: L.t("kb.project.new"), value: "__new__", isNew: true)
                ForEach(projects, id: \.self) { p in
                    projectChip(title: p, value: p, isNew: false)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func projectChip(title: String, value: String, isNew: Bool) -> some View {
        let isActive = project == value
        Button {
            withAnimation(.easeInOut(duration: 0.12)) { project = value }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    isActive ? Color(red: 0.85, green: 0.55, blue: 0.1) : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabPill(label: String, tab: KeyboardTab, activeColor: Color) -> some View {
        let isActive = activeTab == tab && screen == .main
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeTab = tab
                flowState = .modeSelection
            }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? activeColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .history:
            HistoryView { snap in onInsertText(snap.restoreContext()) }
        case .main:
            switch activeTab {
            case .transfer:
                TransferView(flowState: $flowState, llmName: llmName,
                             targetProject: project, onInsertText: onInsertText)
            case .prompts:
                PromptsView(onInsert: onInsertText)
            }
        }
    }
}
