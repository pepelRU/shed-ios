import SwiftUI

@main
@MainActor
struct ShedApp: App {
    @StateObject private var services = AppServices.shared
    @StateObject private var preferences = AppServices.shared.preferences

    init() {
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(preferences)
                .environmentObject(services.repository)
                .environmentObject(services.dnevnikAuth)
                .environmentObject(services.updateChecker)
                .preferredColorScheme(preferences.themeMode.colorScheme)
                .task { BackgroundRefresh.schedule() }
        }
    }
}
