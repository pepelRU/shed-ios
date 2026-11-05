import Foundation
import Combine

enum ScheduleRefreshPeriod: String, CaseIterable, Codable {
    case todayAndTomorrow
    case currentWeek
    case twoWeeks

    var title: String {
        switch self {
        case .todayAndTomorrow: return "Сегодня и завтра"
        case .currentWeek: return "На текущую неделю"
        case .twoWeeks: return "На текущую и следующую неделю"
        }
    }
}

enum ThemeMode: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "Системное"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
}

@MainActor
final class SchedulePreferences: ObservableObject {
    @Published var subgroup: Int {
        didSet { defaults.set(subgroup, forKey: Keys.subgroup) }
    }

    @Published var refreshPeriod: ScheduleRefreshPeriod {
        didSet { defaults.set(refreshPeriod.rawValue, forKey: Keys.refreshPeriod) }
    }

    @Published var themeMode: ThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedSubgroup = defaults.integer(forKey: Keys.subgroup)
        subgroup = (1...2).contains(storedSubgroup) ? storedSubgroup : 1
        refreshPeriod = ScheduleRefreshPeriod(rawValue: defaults.string(forKey: Keys.refreshPeriod) ?? "") ?? .currentWeek
        themeMode = ThemeMode(rawValue: defaults.string(forKey: Keys.themeMode) ?? "") ?? .system
    }

    func currentGroup() -> String { "ПР126" }

    private enum Keys {
        static let subgroup = "shed.subgroup"
        static let refreshPeriod = "shed.refreshPeriod"
        static let themeMode = "shed.themeMode"
    }
}
