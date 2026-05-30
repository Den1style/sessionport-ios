import SwiftUI

@main
struct SessionPortApp: App {
    @StateObject private var drive = GoogleDriveService.shared
    @StateObject private var store = StoreKitService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(drive)
                .environmentObject(store)
        }
    }
}
