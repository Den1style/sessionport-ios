import UIKit
import Foundation

// Copies text to pasteboard and automatically clears it after the given interval.
// Prevents sensitive context from lingering in clipboard (MASVS-STORAGE-2 / MASTG-TEST-0053).
// Must be called from @MainActor context (UIPasteboard is main-actor bound in Swift 6).
@MainActor
func copyWithExpiration(_ text: String, after seconds: Double = 60) {
    UIPasteboard.general.string = text
    let copied = text
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(seconds))
        // Only clear if our text is still on the clipboard (user hasn't replaced it)
        if UIPasteboard.general.string == copied {
            UIPasteboard.general.string = ""
        }
    }
}
