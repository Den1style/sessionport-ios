import SwiftUI
import UIKit

@main
struct SessionPortApp: App {
    @StateObject private var drive = GoogleDriveService.shared
    @StateObject private var store = StoreKitService.shared
    @StateObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(drive)
                .environmentObject(store)
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
        }
        // Background screenshot protection (MASVS-STORAGE-2 / MASTG-TEST-0058):
        // blur sensitive content when app moves to background so it won't
        // appear in the system app-switcher screenshot.
        .onChange(of: scenePhase) { _, phase in
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else { return }

            if phase == .background {
                let blur = UIBlurEffect(style: .systemThickMaterial)
                let blurView = UIVisualEffectView(effect: blur)
                blurView.frame = window.bounds
                blurView.tag = 9999
                blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                window.addSubview(blurView)
            } else {
                window.viewWithTag(9999)?.removeFromSuperview()
            }
        }
    }
}
