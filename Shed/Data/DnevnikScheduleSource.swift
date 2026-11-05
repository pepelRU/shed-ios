import Foundation
import Combine

@MainActor
final class DnevnikScheduleSource {
    private let store: DnevnikSessionStore
    private let client: DnevnikScheduleClient
    private let groupName: String
    private var semesters: [String: DnevnikTable] = [:]

    init(store: DnevnikSessionStore, group: String = DnevnikScheduleParser.groupName) {
        self.store = store
        self.groupName = group
        client = DnevnikScheduleClient(store: store)
    }

    var hasSession: Bool { store.read() != nil }

    func forgetSession() {
        store.clear()
        semesters.removeAll()
    }

    func load(
        dates: [Date],
        progress: (Int, Int) -> Void = { _, _ in }
    ) async throws -> [ScheduleDay] {
        guard !dates.isEmpty else { return [] }
        var days: [Date: ScheduleDay] = [:]
        var done = 0

        let grouped = Dictionary(grouping: dates, by: { ScheduleCalendar.weekStart($0) })
            .sorted { $0.key < $1.key }

        for (monday, weekDates) in grouped {
            let fullWeek = (0...6).map { ScheduleCalendar.adding(days: $0, to: monday) }
            let week = try await fetchWeek(monday: monday, weekDates: fullWeek)
            guard let periodID = week.periodId else {
                throw DnevnikScheduleError(
                    code: "markup",
                    message: "Дневник.ру не указал период расписания"
                )
            }
            let semesterTable = try await loadSemester(periodID)
            let slots = try DnevnikScheduleParser.join(week: week, semester: semesterTable)

            for date in dates where weekDates.contains(where: { ScheduleCalendar.sameDay($0, date) }) {
                let lessons = (slots[date] ?? []).compactMap { lesson($0) }
                days[date] = ScheduleDay(
                    date: date,
                    group: groupName,
                    lessons: lessons,
                    hasChanges: lessons.contains { $0.changed },
                    lastUpdated: Date(),
                    academicWeek: LocalBaseSchedule.weekNumber(for: date)
                )
                done += 1
                progress(done, dates.count)
            }
        }

        return dates.compactMap { days[$0] }
    }

    private func fetchWeek(monday: Date, weekDates: [Date]) async throws -> DnevnikTable {
        do {
            let html = try await client.load(DnevnikScheduleParser.scheduleURL(date: monday))
            return try DnevnikScheduleParser.parse(
                html: html,
                semester: false,
                expectedDates: weekDates
            )
        } catch let error as DnevnikScheduleError {
            throw error
        } catch {
            throw DnevnikScheduleError(code: "network", message: "Не удалось загрузить расписание Дневник.ру")
        }
    }

    private func loadSemester(_ period: String) async throws -> DnevnikTable {
        if let cached = semesters[period] { return cached }
        do {
            let html = try await client.load(DnevnikScheduleParser.scheduleURL(period: period))
            let table = try DnevnikScheduleParser.parse(html: html, semester: true)
            semesters[period] = table
            return table
        } catch let error as DnevnikScheduleError {
            throw error
        } catch {
            throw DnevnikScheduleError(code: "network", message: "Не удалось загрузить расписание Дневник.ру")
        }
    }

    /// A cancelled predecessor becomes the original values of the active lesson.
    private func lesson(_ slot: DnevnikSlot) -> Lesson? {
        let current = slot.lesson
        guard let start = current.startMinutes, let end = current.endMinutes else { return nil }
        let original = slot.replaced.first
        let kinds: Set<LessonChangeKind>
        if let original, !current.cancelled {
            kinds = difference(original, current)
        } else {
            kinds = []
        }
        return Lesson(
            number: current.number,
            startMinutes: start,
            endMinutes: end,
            subject: current.subject,
            teacher: current.teacher,
            room: current.room,
            subgroup: current.subgroup == 1 ? "1" : current.subgroup == 2 ? "2" : "",
            originalNumber: kinds.contains(.time) ? original?.number : nil,
            originalSubject: kinds.contains(.subject) ? (original?.subject ?? "") : "",
            originalTeacher: kinds.contains(.teacher) ? (original?.teacher ?? "") : "",
            originalRoom: kinds.contains(.room) ? (original?.room ?? "") : "",
            cancelled: current.cancelled,
            changed: !kinds.isEmpty,
            changeKinds: kinds
        )
    }

    private func difference(_ original: DnevnikLesson, _ current: DnevnikLesson) -> Set<LessonChangeKind> {
        var kinds: Set<LessonChangeKind> = []
        if original.subject != current.subject { kinds.insert(.subject) }
        if original.teacher != current.teacher { kinds.insert(.teacher) }
        if original.room != current.room { kinds.insert(.room) }
        if original.number != current.number
            || original.startMinutes != current.startMinutes
            || original.endMinutes != current.endMinutes {
            kinds.insert(.time)
        }
        return kinds
    }
}

@MainActor
final class DnevnikAuth: ObservableObject {
    @Published private(set) var state: DnevnikAuthState

    let store: DnevnikSessionStore

    init(store: DnevnikSessionStore) {
        self.store = store
        state = DnevnikAuthState(
            message: store.read() == nil
                ? "Не авторизован"
                : "Сессия действует · расписание из Дневник.ру"
        )
    }

    var isSignedIn: Bool { store.read() != nil }

    func save(_ session: DnevnikSession) {
        store.save(session)
        state = DnevnikAuthState(message: "Расписание из Дневник.ру подключено")
    }

    func signOut() {
        store.clear()
        state = DnevnikAuthState(message: "Не авторизован")
    }

    func sessionInvalidated() {
        store.clear()
        state = DnevnikAuthState(message: "Нужен повторный вход в Дневник.ру")
    }
}
