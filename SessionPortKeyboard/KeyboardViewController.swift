import UIKit
import SwiftUI

private let kLLMBundleIDs: Set<String> = [
    "com.anthropic.claudeios",
    "com.openai.chat",
    "com.google.Bard",
    "com.google.GeminiApp",
    "ai.perplexity.perplexity-ios",
    "ai.mistral.ios",
    "ai.grok.ios",
    "com.x.twitter",
    "com.deepmind.gemini",
]

private let kLLMNames: [String: String] = [
    "com.anthropic.claudeios":      "Claude",
    "com.openai.chat":              "ChatGPT",
    "com.google.Bard":              "Gemini",
    "com.google.GeminiApp":         "Gemini",
    "ai.perplexity.perplexity-ios": "Perplexity",
    "ai.mistral.ios":               "Mistral",
    "ai.grok.ios":                  "Grok",
    "com.x.twitter":                "Grok",
    "com.deepmind.gemini":          "Gemini",
]

private let kExpandedHeight: CGFloat = 220
private let kStripHeight:    CGFloat = 28

final class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardPanelView>?
    private var stripView: StripView?

    // Height constraint on inputView — the correct way for keyboard extensions
    private var heightConstraint: NSLayoutConstraint?

    private var isLLMApp  = false
    private var llmName   = ""
    private var isExpanded = false
    private var lastDetectedBundleID = ""

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        detectLLMContext()
        setupHeightConstraint()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Only rebuild UI if host app changed (avoids flicker on every appearance)
        let bundleID = hostBundleID()
        guard bundleID != lastDetectedBundleID else { return }
        lastDetectedBundleID = bundleID
        detectLLMContext()
        tearDown()
        setupUI()
    }

    // MARK: - Height (keyboard extension pattern)

    private func setupHeightConstraint() {
        // Remove existing height constraints to avoid conflicts
        view.constraints.filter { $0.firstAttribute == .height }.forEach { view.removeConstraint($0) }
        let h = view.heightAnchor.constraint(equalToConstant: kStripHeight)
        h.priority = .required
        h.isActive = true
        heightConstraint = h
    }

    private func setHeight(_ h: CGFloat) {
        guard heightConstraint?.constant != h else { return }
        heightConstraint?.constant = h
        view.setNeedsLayout()
    }

    // MARK: - LLM Detection

    private func hostBundleID() -> String {
        (value(forKey: "hostBundleID") as? String) ?? ""
    }

    private func detectLLMContext() {
        let bundleID = hostBundleID()
        isLLMApp = kLLMBundleIDs.contains(bundleID)
        llmName  = kLLMNames[bundleID] ?? ""
    }

    // MARK: - UI

    private func setupUI() {
        if isLLMApp {
            isExpanded = true
            showPanel()
            setHeight(kExpandedHeight)
        } else {
            isExpanded = false
            showStrip(isLLM: false)
            setHeight(kStripHeight)
        }
    }

    private func tearDown() {
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
        stripView?.removeFromSuperview()
        stripView = nil
    }

    // MARK: - Panel

    private func showPanel() {
        let panel = KeyboardPanelView(
            llmName: llmName,
            onInsertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            onCollapse:   { [weak self] in self?.collapseToStrip() }
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

    private func collapseToStrip() {
        isExpanded = false
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
        showStrip(isLLM: true)
        UIView.animate(withDuration: 0.2) { self.setHeight(kStripHeight) }
    }

    // MARK: - Strip

    private func showStrip(isLLM: Bool) {
        let strip = StripView(isLLM: isLLM) { [weak self] in
            guard let self else { return }
            if self.isLLMApp { self.expandFromStrip() }
            else { self.showNonLLMToast() }
        }
        strip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            strip.topAnchor.constraint(equalTo: view.topAnchor),
            strip.heightAnchor.constraint(equalToConstant: kStripHeight),
        ])
        stripView = strip
    }

    private func expandFromStrip() {
        isExpanded = true
        stripView?.removeFromSuperview()
        stripView = nil
        showPanel()
        UIView.animate(withDuration: 0.2) { self.setHeight(kExpandedHeight) }
    }

    private func showNonLLMToast() {
        let toast = UILabel()
        toast.text = "Works only in LLM apps (Claude, ChatGPT, Gemini…)"
        toast.font = .systemFont(ofSize: 12)
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 8
        toast.clipsToBounds = true
        toast.alpha = 0
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.9),
            toast.heightAnchor.constraint(equalToConstant: 24),
        ])
        UIView.animate(withDuration: 0.15) { toast.alpha = 1 }
        UIView.animate(withDuration: 0.2, delay: 1.8) { toast.alpha = 0 } completion: { _ in
            toast.removeFromSuperview()
        }
    }
}

// MARK: - StripView

final class StripView: UIView {
    private let isLLM: Bool
    private let onTap: () -> Void

    init(isLLM: Bool, onTap: @escaping () -> Void) {
        self.isLLM = isLLM
        self.onTap = onTap
        super.init(frame: .zero)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = isLLM
            ? UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 0.9)
            : UIColor.systemGray5
        let label = UILabel()
        label.text = isLLM ? "——— ∨ ———" : "——— ∨ ———"
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = isLLM ? .white : .tertiaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    @objc private func tapped() { onTap() }
}
