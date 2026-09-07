import SwiftUI

@main
struct XanaTokenMonitorWatchOSApp: App {
    @State private var providerManager = ProviderManager()

    var body: some Scene {
        WindowGroup {
            ProviderListView(providerManager: providerManager)
        }
    }
}
