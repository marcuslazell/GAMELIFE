import SwiftUI

@main
struct GAMELIFEWatchApp: App {
    @StateObject private var sessionStore = WatchSessionStore()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(sessionStore)
        }
    }
}
