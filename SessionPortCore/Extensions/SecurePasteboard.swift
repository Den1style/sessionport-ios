import UIKit
import Foundation

// Copies text to pasteboard and automatically clears it after the given interval.
// Prevents sensitive context from lingering in clipboard (MASVS-STORAGE-2 / MASTG-TEST-0053).
// Must be called from @MainActor context (UIPasteboard is main-actor bound in Swift 6).
@MainActor
func copyWithExpiration(_ text: String, after seconds: Double = 60) {
    // Native options so iOS enforces them even if the app is killed:
    //  • .localOnly      → never synced to other devices via Universal Clipboard
    //  • .expirationDate → system auto-clears after the interval
    let item = [UIPasteboard.typeAutomatic: text as Any]
    UIPasteboard.general.setItems(
        [item],
        options: [
            .localOnly: true,
            .expirationDate: Date().addingTimeInterval(seconds),
        ]
    )
    // Belt-and-suspenders: also clear in-process if our text is still there.
    let copied = text
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(seconds))
        if UIPasteboard.general.string == copied {
            UIPasteboard.general.string = ""
        }
    }
}
