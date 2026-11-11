import SwiftUI

@main
struct SamsungRemoteApp: App {
    @StateObject private var tv = TVController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tv)
        }
    }
}
