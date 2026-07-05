import SwiftUI
import UIKit

// MARK: - Map controller — drives zoom + fork/link modes

@MainActor
final class MapController: ObservableObject {
    enum Mode: Equatable { case none, fork, link }
    @Published var mode: Mode = .none
    @Published var linkSource: String? = nil
    @Published var banner: String? = nil
    weak var canvas: MapCanvasView?

    func zoomIn()  { canvas?.zoom(by: 1.25) }
    func zoomOut() { canvas?.zoom(by: 0.8) }
    func reset()   { canvas?.resetView() }

    func startFork() {
        mode = .fork; linkSource = nil
        banner = "Ветка: выберите узел — от него пойдёт следующий перенос"
    }
    func startLink() {
        mode = .link; linkSource = nil
        banner = "Связь: выберите родителя"
    }
    func cancel() { mode = .none; linkSource = nil; banner = nil }
}

// MARK: - Container (no Dashboard — just the interactive graph)

struct MindMapContainerView: View {
    @StateObject private var map = MapController()
    @State private var snapshots = SharedStorage.shared.activeSnapshots
    @State private var selectedProject: String? = nil
    @State private var selectedId: String? = nil

    private var projects: [String] { SharedStorage.shared.allProjects }

    private var displayed: [Snapshot] {
        guard let proj = selectedProject else { return snapshots }
        return snapshots.filter { $0.project == proj }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    Divider()
                }

                MapToolbarView(map: map)

                // Mode banner
                if let banner = map.banner {
                    HStack(spacing: 8) {
                        Text(banner)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        if map.mode != .none {
                            Button("Отмена") { map.cancel() }
                                .font(.system(size: 12))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.08))
                }

                ZStack {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                    if displayed.isEmpty {
                        ContentUnavailableView(
                            "Нет снэпшотов",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text("Используй клавиатуру SessionPort для захвата контекста")
                        )
                    } else {
                        MapCanvasRepresentable(
                            snapshots: displayed,
                            selectedId: selectedId,
                            register: { map.canvas = $0 },
                            onTap: handleTap
                        )
                        .ignoresSafeArea(edges: .bottom)

                        if map.mode == .none, let id = selectedId,
                           let snap = displayed.first(where: { $0.id == id }) {
                            MapInfoPanel(snapshot: snap, onDismiss: { selectedId = nil })
                                .padding(.horizontal, 12)
                                .padding(.bottom, 16)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .animation(.spring(response: 0.3), value: selectedId)
            }
            .navigationTitle("Mind Map")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { snapshots = SharedStorage.shared.activeSnapshots }
        }
    }

    private func handleTap(_ id: String) {
        switch map.mode {
        case .none:
            selectedId = id.isEmpty ? nil : (selectedId == id ? nil : id)

        case .fork:
            guard !id.isEmpty, let node = snapshots.first(where: { $0.id == id }) else {
                map.cancel(); return
            }
            SharedStorage.shared.kbForkParentId = id
            SharedStorage.shared.kbProject = node.project ?? "__new__"
            map.mode = .none
            map.banner = "Ветка от «\(node.title.prefix(24))» — открой клавиатуру и сделай перенос"

        case .link:
            guard !id.isEmpty else { map.cancel(); return }
            if let parent = map.linkSource {
                SharedStorage.shared.setParent(of: id, to: parent)   // id becomes child of parent
                snapshots = SharedStorage.shared.activeSnapshots
                map.cancel()
            } else {
                map.linkSource = id
                map.banner = "Связь: теперь выберите потомка"
            }
        }
    }
}

// MARK: - Project chip

struct ProjectChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(
                    isActive ? Color.accentColor.opacity(0.12) : Color(UIColor.secondarySystemBackground),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toolbar

struct MapToolbarView: View {
    @ObservedObject var map: MapController

    var body: some View {
        HStack(spacing: 6) {
            ToolBtn(label: "+ Ветка", color: .green, active: map.mode == .fork) {
                map.mode == .fork ? map.cancel() : map.startFork()
            }
            ToolBtn(label: "🔗 Связь", color: .blue, active: map.mode == .link) {
                map.mode == .link ? map.cancel() : map.startLink()
            }
            Spacer()
            ToolBtn(label: "+", color: .secondary, width: 32) { map.zoomIn() }
            ToolBtn(label: "−", color: .secondary, width: 32) { map.zoomOut() }
            ToolBtn(label: "⊙", color: .secondary, width: 32) { map.reset() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }
}

struct ToolBtn: View {
    let label: String
    let color: Color
    var width: CGFloat? = nil
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? .white : (color == .secondary ? .secondary : color))
                .frame(width: width)
                .padding(.horizontal, width == nil ? 10 : 0)
                .padding(.vertical, 5)
                .background(
                    active ? color : (color == .secondary ? Color(UIColor.secondarySystemBackground) : color.opacity(0.1)),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(color == .secondary ? Color.clear : color.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Map info panel

struct MapInfoPanel: View {
    let snapshot: Snapshot
    let onDismiss: () -> Void
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(llmColor(snapshot.llmSource)).frame(width: 10, height: 10)
                Text(snapshot.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text(snapshot.llmSource.capitalized)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                Text(snapshot.createdAt, style: .relative)
                    .font(.caption).foregroundStyle(.secondary)
                if let proj = snapshot.project {
                    Text(proj).font(.caption).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
            }

            if !snapshot.goal.isEmpty {
                Text(snapshot.goal)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button {
                copyWithExpiration(snapshot.restoreContext())
                showCopied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); showCopied = false }
            } label: {
                Label(showCopied ? "Скопировано ✓" : "Загрузить слепок", systemImage: "arrow.up.doc.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func llmColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "claude": return .orange; case "chatgpt": return .green
        case "gemini": return .blue; case "grok": return .primary
        case "perplexity": return .purple; default: return .gray
        }
    }
}

// MARK: - UIViewRepresentable canvas

struct MapCanvasRepresentable: UIViewRepresentable {
    let snapshots: [Snapshot]
    let selectedId: String?
    let register: (MapCanvasView) -> Void   // hand the view to MapController for zoom
    let onTap: (String) -> Void             // "" == background tap

    func makeUIView(context: Context) -> MapCanvasView {
        let v = MapCanvasView()
        v.onNodeTap = onTap
        register(v)
        return v
    }

    func updateUIView(_ v: MapCanvasView, context: Context) {
        v.onNodeTap = onTap
        v.setSnapshots(snapshots, selectedId: selectedId)
    }
}

// MARK: - MapCanvasView (UIView with pan + zoom + tap)

final class MapCanvasView: UIView {
    var onNodeTap: ((String) -> Void)?

    private var snapshots: [Snapshot] = []
    private var selectedId: String? = nil
    private var positions: [String: CGPoint] = [:]

    // Pan & zoom state
    private var scale: CGFloat = 1
    private var offset: CGPoint = .zero
    private var lastPanLoc: CGPoint = .zero
    private var isPanning = false

    private let nodeColors: [UIColor] = [
        .systemOrange, .systemGreen, .systemBlue,
        .systemPurple, .systemRed, .systemTeal, .systemYellow
    ]
    private var colorMap: [String: UIColor] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        [pan, pinch, tap].forEach { addGestureRecognizer($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSnapshots(_ snaps: [Snapshot], selectedId: String?) {
        self.snapshots = snaps
        self.selectedId = selectedId
        recomputeLayout()
        setNeedsDisplay()
    }

    // MARK: - Zoom controls (toolbar)

    func zoom(by factor: CGFloat) {
        scale = max(0.3, min(3.0, scale * factor))
        setNeedsDisplay()
    }

    func resetView() {
        scale = 1
        if snapshots.isEmpty {
            offset = .zero
        } else {
            let allX = positions.values.map { $0.x }
            let minX = allX.min() ?? 0
            let maxX = allX.max() ?? bounds.width
            offset = CGPoint(x: bounds.midX - (minX + maxX) / 2, y: 20)
        }
        setNeedsDisplay()
    }

    private func recomputeLayout() {
        positions = [:]
        colorMap = [:]
        // A node is a root if it has no parent OR its parent is not in the current
        // set (parent was trashed or filtered out by project). Without this,
        // descendants of a missing parent would never be positioned and would
        // silently vanish from the map — broken inheritance display.
        let idSet = Set(snapshots.map { $0.id })
        let roots = snapshots.filter { snap in
            guard let pid = snap.parentId else { return true }
            return !idSet.contains(pid)
        }
        let colW: CGFloat = max(120, bounds.width / CGFloat(max(roots.count, 1)))
        let rowH: CGFloat = 110

        var visited = Set<String>()
        for (ci, root) in roots.enumerated() {
            colorMap[root.id] = nodeColors[ci % nodeColors.count]
            let cx = colW * CGFloat(ci) + colW / 2
            positions[root.id] = CGPoint(x: cx, y: 60)
            visited.insert(root.id)
            layoutChildren(of: root.id, parentPos: CGPoint(x: cx, y: 60),
                           depth: 1, rowH: rowH, colW: colW, colorIndex: ci, visited: &visited)
        }
    }

    private func layoutChildren(of parentId: String, parentPos: CGPoint,
                                depth: Int, rowH: CGFloat, colW: CGFloat, colorIndex: Int,
                                visited: inout Set<String>) {
        // Guard against cycles in malformed/imported data (would otherwise recurse forever)
        let children = snapshots.filter { $0.parentId == parentId && !visited.contains($0.id) }
        let spread = colW
        for (i, child) in children.enumerated() {
            visited.insert(child.id)
            let offset = (CGFloat(i) - CGFloat(children.count - 1) / 2) * spread
            let pos = CGPoint(x: parentPos.x + offset, y: parentPos.y + rowH)
            positions[child.id] = pos
            colorMap[child.id] = nodeColors[colorIndex % nodeColors.count]
            layoutChildren(of: child.id, parentPos: pos, depth: depth + 1,
                           rowH: rowH, colW: colW, colorIndex: colorIndex, visited: &visited)
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Apply pan + zoom transform
        ctx.saveGState()
        ctx.translateBy(x: offset.x, y: offset.y)
        ctx.scaleBy(x: scale, y: scale)

        drawEdges(ctx)
        drawNodes(ctx)

        ctx.restoreGState()
    }

    private func drawEdges(_ ctx: CGContext) {
        ctx.setLineWidth(1.5 / scale)
        for snap in snapshots {
            guard let pid = snap.parentId,
                  let from = positions[pid], let to = positions[snap.id] else { continue }
            let col = colorMap[pid] ?? .systemGray
            ctx.setStrokeColor(col.withAlphaComponent(0.25).cgColor)
            // Curved edge
            let cp1 = CGPoint(x: from.x, y: from.y + (to.y - from.y) * 0.5)
            let cp2 = CGPoint(x: to.x, y: to.y - (to.y - from.y) * 0.5)
            let path = UIBezierPath()
            path.move(to: from)
            path.addCurve(to: to, controlPoint1: cp1, controlPoint2: cp2)
            ctx.addPath(path.cgPath)
            ctx.strokePath()
        }
    }

    private func drawNodes(_ ctx: CGContext) {
        for snap in snapshots {
            guard let pos = positions[snap.id] else { continue }
            let col = colorMap[snap.id] ?? .systemGray
            let isRoot = snap.parentId == nil
            let isSel = snap.id == selectedId
            let r: CGFloat = isRoot ? 11 : 8

            // Glow for root
            if isRoot {
                ctx.setFillColor(col.withAlphaComponent(0.15).cgColor)
                let gr = r + 5
                ctx.fillEllipse(in: CGRect(x: pos.x - gr, y: pos.y - gr, width: gr * 2, height: gr * 2))
            }

            // Node
            ctx.setFillColor(isSel ? UIColor.white.cgColor : col.cgColor)
            ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2))

            // Selected ring
            if isSel {
                ctx.setStrokeColor(col.cgColor)
                ctx.setLineWidth(2.5 / scale)
                ctx.strokeEllipse(in: CGRect(x: pos.x - r - 2, y: pos.y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2))
            }

            // Label
            let label = snap.title.count > 16 ? String(snap.title.prefix(15)) + "…" : snap.title
            let fontSize: CGFloat = isRoot ? 9.5 : 8.5
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize / scale, weight: isRoot ? .semibold : .regular),
                .foregroundColor: isSel ? col : UIColor.label.withAlphaComponent(isRoot ? 0.8 : 0.55),
            ]
            let size = (label as NSString).size(withAttributes: attrs)
            let lx = pos.x - size.width / 2
            let ly = pos.y + r + 3 / scale
            (label as NSString).draw(at: CGPoint(x: lx, y: ly), withAttributes: attrs)
        }
    }

    // MARK: - Gestures

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let loc = g.location(in: self)
        switch g.state {
        case .began: lastPanLoc = loc
        case .changed:
            offset.x += loc.x - lastPanLoc.x
            offset.y += loc.y - lastPanLoc.y
            lastPanLoc = loc
            setNeedsDisplay()
        default: break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .changed {
            let newScale = max(0.3, min(3.0, scale * g.scale))
            scale = newScale
            g.scale = 1
            setNeedsDisplay()
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let raw = g.location(in: self)
        // Convert to canvas space
        let cx = (raw.x - offset.x) / scale
        let cy = (raw.y - offset.y) / scale
        let pt = CGPoint(x: cx, y: cy)

        for (id, pos) in positions {
            let snap = snapshots.first { $0.id == id }
            let r: CGFloat = snap?.parentId == nil ? 14 : 11
            if hypot(pt.x - pos.x, pt.y - pos.y) < r {
                onNodeTap?(id)
                return
            }
        }
        // Tap on empty → deselect
        onNodeTap?("")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        recomputeLayout()
        // Center the graph initially
        if !snapshots.isEmpty && offset == .zero {
            let allX = positions.values.map { $0.x }
            let minX = allX.min() ?? 0
            let maxX = allX.max() ?? bounds.width
            let midX = (minX + maxX) / 2
            offset = CGPoint(x: bounds.midX - midX * scale, y: 20)
        }
        setNeedsDisplay()
    }
}
