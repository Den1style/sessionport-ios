import UIKit
import SwiftUI

// Shared with KeyboardPanelView so the constraint and the SwiftUI panel agree.
private let kExpandedHeight: CGFloat = kbExpandedHeight

final class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardPanelView>?

    private var heightConstraint: NSLayoutConstraint?
    private var targetHeight: CGFloat = kExpandedHeight

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        showPanel()
    }

    // ── Height without the switch-in jump ──
    // `allowsSelfSizing` is the supported way for a keyboard to dictate its own
    // height: the system adopts our constraint from the very first layout pass,
    // so the panel slides in at targetHeight directly. The previous approach
    // (mutating the constant mid-presentation to outsmart the system's
    // `UIView-Encapsulated-Layout-Height`) was itself the visible jump.
    // The constraint is created here, not in viewDidLoad — before the view is in
    // the hierarchy the system hasn't installed its own height yet, and adding
    // ours too early triggers an animated correction.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inputView?.allowsSelfSizing = true
        if heightConstraint == nil {
            let h = view.heightAnchor.constraint(equalToConstant: targetHeight)
            h.priority = UILayoutPriority(rawValue: 999)
            h.isActive = true
            heightConstraint = h
        }
    }

    // MARK: - Clear inserted text

    private func clearText() {
        let proxy = textDocumentProxy
        // Move the cursor to the end, then delete everything before it.
        var safety = 0
        while let after = proxy.documentContextAfterInput, !after.isEmpty, safety < 2000 {
            proxy.adjustTextPosition(byCharacterOffset: after.count)
            safety += 1
        }
        safety = 0
        while let before = proxy.documentContextBeforeInput, !before.isEmpty, safety < 20000 {
            proxy.deleteBackward()
            safety += 1
        }
    }

    // MARK: - Panel

    private func showPanel() {
        let panel = KeyboardPanelView(
            llmName: "",
            onInsertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            onClear:      { [weak self] in self?.clearText() }
        )
        let hc = UIHostingController(rootView: panel)
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hc)
        view.addSubview(hc.view)
        NSLayoutConstraint.activate([
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hc.didMove(toParent: self)
        hostingController = hc
    }
}
