import SwiftUI

@main
struct SamsungRemoteApp: App {
    @StateObject private var tv = TVController()
    @StateObject private var discovery = TVDiscovery()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tv)
                .environmentObject(discovery)
        }
    }
}
