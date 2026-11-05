import SwiftUI

@main
@MainActor
struct ShedApp: App {
    @StateObject private var services = AppServices.shared

    init() {
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(services.preferences)
                .environmentObject(services.repository)
                .environmentObject(services.dnevnikAuth)
                .environmentObject(services.updateChecker)
                .preferredColorScheme(services.preferences.themeMode.colorScheme)
                .task { BackgroundRefresh.schedule() }
        }
    }
}
