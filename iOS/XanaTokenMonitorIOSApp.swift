import SwiftUI
import XanaTokenMonitorKit

@main
struct XanaTokenMonitorIOSApp: App {
    @State private var providerManager = ProviderManager()

    var body: some Scene {
        WindowGroup {
            ProviderListView(providerManager: providerManager)
        }
    }
}
