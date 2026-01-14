import SwiftUI

@main
struct SecureWaveApp: App {
    @StateObject private var session = UserSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}
