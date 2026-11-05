import Foundation
import Combine

@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let preferences: SchedulePreferences
    let dnevnikAuth: DnevnikAuth
    let repository: ScheduleRepository
    let updateChecker: UpdateChecker

    private init() {
        let preferences = SchedulePreferences()
        let store = KeychainDnevnikSessionStore()
        let auth = DnevnikAuth(store: store)
        let dnevnik = DnevnikScheduleSource(store: store)
        let repository = ScheduleRepository(
            preferences: preferences,
            cache: ScheduleCache(),
            remote: ScheduleRemoteDataSource(),
            parser: ScheduleHtmlParser(),
            dnevnik: dnevnik,
            dnevnikAuth: auth
        )

        self.preferences = preferences
        dnevnikAuth = auth
        self.repository = repository
        updateChecker = UpdateChecker()
    }
}
