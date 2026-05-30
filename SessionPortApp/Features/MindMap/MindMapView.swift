import SwiftUI
import UIKit

enum MindMapTab { case map, dashboard }

struct MindMapContainerView: View {
    @State private var activeTab: MindMapTab = .map
    @State private var snapshots = SharedStorage.shared.snapshots
    @State private var filter: String? = nil  // nil = All

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab switcher: Map / Dashboard
                Picker("", selection: $activeTab) {
                    Text("Mind Map").tag(MindMapTab.map)
                    Text("Dashboard").tag(MindMapTab.dashboard)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if activeTab == .map {
                    MindMapGraphView(snapshots: snapshots)
                } else {
                    DashboardView(snapshots: snapshots, filter: $filter)
                }
            }
            .navigationTitle("Mind Map")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { snapshots = SharedStorage.shared.snapshots }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    let snapshots: [Snapshot]
    @Binding var filter: String?

    private var llmSources: [String] {
        Array(Set(snapshots.map { $0.llmSource.lowercased() })).sorted()
    }

    private var filtered: [Snapshot] {
        guard let f = filter else { return snapshots }
        return snapshots.filter { $0.llmSource.lowercased() == f }
    }

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(label: "All", isActive: filter == nil) { filter = nil }
                    ForEach(llmSources, id: \.self) { src in
                        FilterChip(label: src.capitalized, isActive: filter == src) { filter = src }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            Divider()

            if filtered.isEmpty {
                ContentUnavailableView("No snapshots", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(filtered) { snap in
                            DashboardCard(snapshot: snap)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}

struct FilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.green : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isActive
                        ? Color.green.opacity(0.12)
                        : Color(UIColor.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DashboardCard: View {
    let snapshot: Snapshot
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(snapshot.createdAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                Circle()
                    .fill(llmColor(snapshot.llmSource))
                    .frame(width: 8, height: 8)
                    .padding(.top, 3)
            }

            // LLM + files badges
            HStack(spacing: 4) {
                Text(snapshot.llmSource.isEmpty ? "Unknown" : snapshot.llmSource.capitalized)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                if !snapshot.attachedFiles.isEmpty {
                    Text("📎 \(snapshot.attachedFiles.count)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            // Goal preview
            if !snapshot.goal.isEmpty {
                Text(snapshot.goal)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            // Actions
            HStack(spacing: 6) {
                Button {
                    UIPasteboard.general.string = snapshot.contextText()
                    showCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        showCopied = false
                    }
                } label: {
                    Text(showCopied ? "✓" : "Load ↑")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.6, green: 0.44, blue: 1.0))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.13),
                                    in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
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

// MARK: - Graph

struct MindMapGraphView: View {
    let snapshots: [Snapshot]
    @State private var selectedId: String? = nil

    var body: some View {
        ZStack {
            Color(red: 0.031, green: 0.047, blue: 0.071)
                .ignoresSafeArea()

            if snapshots.isEmpty {
                Text("No snapshots yet")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
            } else {
                // Toolbar
                VStack {
                    HStack(spacing: 6) {
                        MapToolBtn(label: "+ Branch", style: .green)
                        MapToolBtn(label: "🔗 Link", style: .blue)
                        MapToolBtn(label: "Dashboard", style: .purple) {}
                        Spacer()
                        MapToolBtn(label: "+", style: .plain)
                        MapToolBtn(label: "−", style: .plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemBackground).opacity(0.05))
                    Spacer()
                }

                CanvasView(snapshots: snapshots, selectedId: $selectedId)
            }
        }
    }
}

struct CanvasView: UIViewRepresentable {
    let snapshots: [Snapshot]
    @Binding var selectedId: String?

    func makeUIView(context: Context) -> MapCanvasUIView {
        let v = MapCanvasUIView()
        v.onNodeTap = { [self] id in
            // UIView touches arrive on main thread
            selectedId = id
        }
        return v
    }
    func updateUIView(_ uiView: MapCanvasUIView, context: Context) {
        uiView.setSnapshots(snapshots, selected: selectedId)
    }
}

final class MapCanvasUIView: UIView {
    var onNodeTap: ((String) -> Void)?
    private var snapshots: [Snapshot] = []
    private var selectedId: String? = nil
    private let colors: [UIColor] = [.systemOrange, .systemGreen, .systemBlue, .systemPurple, .systemRed, .systemTeal]

    func setSnapshots(_ snaps: [Snapshot], selected: String?) {
        snapshots = snaps; selectedId = selected
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor(red: 0.031, green: 0.047, blue: 0.071, alpha: 1).cgColor)
        ctx.fill(rect)

        let positions = computePositions(in: rect)

        // Edges
        for snap in snapshots {
            guard let parentId = snap.parentId,
                  let from = positions[parentId],
                  let to = positions[snap.id] else { continue }
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.08).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
        }

        // Nodes
        for (i, snap) in snapshots.enumerated() {
            guard let pos = positions[snap.id] else { continue }
            let isHead = snap.parentId == nil
            let isSelected = snap.id == selectedId
            let col = colors[i % colors.count]
            let r: CGFloat = isHead ? 10 : 7

            // Glow for head
            if isHead {
                ctx.setFillColor(col.withAlphaComponent(0.2).cgColor)
                ctx.fillEllipse(in: CGRect(x: pos.x - r - 4, y: pos.y - r - 4, width: (r + 4) * 2, height: (r + 4) * 2))
            }

            // Node circle
            ctx.setFillColor((isSelected ? UIColor.white : col).cgColor)
            ctx.fillEllipse(in: CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2))

            // Border
            if isSelected {
                ctx.setStrokeColor(col.cgColor); ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: pos.x - r - 1, y: pos.y - r - 1, width: (r + 1) * 2, height: (r + 1) * 2))
            }

            // Label
            let label = String(snap.title.prefix(18)) + (snap.title.count > 18 ? "…" : "")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: isHead ? 8.5 : 7.5, weight: isHead ? .semibold : .regular),
                .foregroundColor: isHead ? UIColor.white.withAlphaComponent(0.8) : UIColor.white.withAlphaComponent(0.45),
            ]
            let size = (label as NSString).size(withAttributes: attrs)
            (label as NSString).draw(at: CGPoint(x: pos.x - size.width / 2, y: pos.y + r + 4), withAttributes: attrs)
        }
    }

    private func computePositions(in rect: CGRect) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        let roots = snapshots.filter { $0.parentId == nil }
        let colW = rect.width / CGFloat(max(roots.count, 1))

        for (ci, root) in roots.enumerated() {
            let cx = colW * CGFloat(ci) + colW / 2
            result[root.id] = CGPoint(x: cx, y: rect.height * 0.18)
            layoutChildren(of: root.id, parent: CGPoint(x: cx, y: rect.height * 0.18),
                           depth: 1, rect: rect, result: &result)
        }
        return result
    }

    private func layoutChildren(of parentId: String, parent: CGPoint, depth: Int, rect: CGRect, result: inout [String: CGPoint]) {
        let children = snapshots.filter { $0.parentId == parentId }
        let spread: CGFloat = rect.width / CGFloat(max(children.count, 1))
        let yStep: CGFloat = rect.height * 0.22
        for (i, child) in children.enumerated() {
            let x = spread * CGFloat(i) + spread / 2
            let y = parent.y + yStep
            result[child.id] = CGPoint(x: x, y: y)
            layoutChildren(of: child.id, parent: CGPoint(x: x, y: y), depth: depth + 1, rect: rect, result: &result)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        let positions = computePositions(in: bounds)
        for (id, pos) in positions {
            if hypot(pt.x - pos.x, pt.y - pos.y) < 16 {
                onNodeTap?(id); return
            }
        }
    }
}

struct MapToolBtn: View {
    let label: String
    enum Style { case green, blue, purple, plain }
    let style: Style
    var action: (() -> Void)? = nil

    var body: some View {
        Button { action?() } label: {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(fgColor)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(bgColor, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var fgColor: Color {
        switch style {
        case .green: return Color(red: 0.29, green: 0.85, blue: 0.47)
        case .blue: return Color(red: 0.58, green: 0.65, blue: 0.98)
        case .purple: return Color(red: 0.77, green: 0.71, blue: 1.0)
        case .default: return .secondary
        }
    }
    private var bgColor: Color {
        switch style {
        case .green: return Color(red: 0.1, green: 0.23, blue: 0.16)
        case .blue: return Color(red: 0.08, green: 0.13, blue: 0.25)
        case .purple: return Color(red: 0.1, green: 0.08, blue: 0.21)
        case .default: return Color(UIColor.systemBackground).opacity(0.06)
        }
    }
    private var borderColor: Color {
        switch style {
        case .green: return Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.3)
        case .blue: return Color(red: 0.23, green: 0.52, blue: 0.96).opacity(0.3)
        case .purple: return Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.3)
        case .default: return Color.secondary.opacity(0.15)
        }
    }
}
