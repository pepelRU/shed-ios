import Foundation

// MARK: - Change model

enum LessonChangeKind: String, Codable, CaseIterable, Hashable {
    case subject
    case teacher
    case time
    case room
    case added
    case cancelled
}

func isDistanceRoom(_ room: String) -> Bool {
    let value = room.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return value == "дис"
        || value.hasPrefix("дистанц")
        || value.hasPrefix("онлайн")
        || value == "online"
}

// MARK: - Lesson

struct Lesson: Identifiable, Codable, Hashable {
    var number: Int
    var startMinutes: Int
    var endMinutes: Int
    var subject: String
    var teacher: String
    var room: String
    var subgroup: String
    var originalNumber: Int?
    var originalSubject: String
    var originalTeacher: String
    var originalRoom: String
    var cancelled: Bool
    var changed: Bool
    var changeKinds: Set<LessonChangeKind>

    init(
        number: Int,
        startMinutes: Int,
        endMinutes: Int,
        subject: String,
        teacher: String = "",
        room: String = "",
        subgroup: String = "",
        originalNumber: Int? = nil,
        originalSubject: String = "",
        originalTeacher: String = "",
        originalRoom: String = "",
        cancelled: Bool = false,
        changed: Bool = false,
        changeKinds: Set<LessonChangeKind> = []
    ) {
        self.number = number
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.subject = subject
        self.teacher = teacher
        self.room = room
        self.subgroup = subgroup
        self.originalNumber = originalNumber
        self.originalSubject = originalSubject
        self.originalTeacher = originalTeacher
        self.originalRoom = originalRoom
        self.cancelled = cancelled
        self.changed = changed
        self.changeKinds = changeKinds
    }

    var id: String { stableKey }

    var stableKey: String {
        "\(number)|\(subgroup.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    var isDistance: Bool { isDistanceRoom(room) }

    var startText: String { Lesson.timeText(startMinutes) }
    var endText: String { Lesson.timeText(endMinutes) }
    var timeText: String { "\(startText)–\(endText)" }

    static func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func minutes(from text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

// MARK: - Day and snapshot

struct ScheduleDay: Identifiable, Codable, Hashable {
    var date: Date
    var group: String
    var lessons: [Lesson]
    var hasChanges: Bool
    var lastUpdated: Date?
    var academicWeek: Int

    var id: Date { date }
}

struct BellTime {
    var start: Int
    var end: Int
}

struct ScheduleChangeSet {
    var date: Date
    var academicWeek: Int?
    var availableDates: Set<Date>
    var bellTimes: [Int: BellTime]
    var lessons: [Lesson]
    var available: Bool
}

struct ScheduleSnapshot: Codable {
    var group: String
    var days: [ScheduleDay]
    var lastUpdated: Date?
    var isRefreshing: Bool
    var errorMessage: String?
    var fromCache: Bool
    var subgroup: Int
    var changesCheckedAt: Date?
    var changesCheckFailed: Bool

    init(
        group: String,
        days: [ScheduleDay],
        lastUpdated: Date? = nil,
        isRefreshing: Bool = false,
        errorMessage: String? = nil,
        fromCache: Bool = false,
        subgroup: Int = 1,
        changesCheckedAt: Date? = nil,
        changesCheckFailed: Bool = false
    ) {
        self.group = group
        self.days = days
        self.lastUpdated = lastUpdated
        self.isRefreshing = isRefreshing
        self.errorMessage = errorMessage
        self.fromCache = fromCache
        self.subgroup = subgroup
        self.changesCheckedAt = changesCheckedAt
        self.changesCheckFailed = changesCheckFailed
    }

    func day(on date: Date) -> ScheduleDay? {
        days.first { ScheduleCalendar.sameDay($0.date, date) }
    }

    static func empty(group: String) -> ScheduleSnapshot {
        ScheduleSnapshot(group: group, days: [])
    }
}

struct ScheduleChangeSummary {
    var lines: [String]

    var isEmpty: Bool { lines.isEmpty }

    static let empty = ScheduleChangeSummary(lines: [])
}

// MARK: - Refresh state

enum ScheduleRefreshStage: String, Equatable {
    case idle
    case checkingPublishedDates
    case loadingChanges
    case applyingChanges
    case saving
    case success
    case error
}

struct ScheduleRefreshProgress: Equatable {
    var current: Int = 0
    var total: Int = 0
}

struct ScheduleRefreshResult {
    var successful: Bool
    var changeSummary: ScheduleChangeSummary = .empty
}

// MARK: - Dnevnik auth state

struct DnevnikAuthState {
    var message: String
    var busy: Bool = false
}

// MARK: - Update state

struct UpdateInfo: Codable, Identifiable {
    var build: Int
    var version: String
    var url: String
    var notes: String?

    var id: Int { build }
}

enum UpdateCheckState {
    case idle
    case checking
    case upToDate
    case available(UpdateInfo)
    case error(String)
}

// MARK: - Errors

enum ScheduleError: LocalizedError {
    case network(String)
    case source(String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .network(let message), .source(let message), .parse(let message):
            return message
        }
    }
}
