import Foundation
import SwiftSoup

struct DnevnikLesson {
    var id: String
    var date: Date
    var number: Int
    var subgroup: Int?
    var subject: String
    var teacher: String
    var room: String
    var startMinutes: Int?
    var endMinutes: Int?
    var changed: Bool
    var cancelled: Bool
}

struct DnevnikTable {
    var dates: [Date]
    var lessons: [DnevnikLesson]
    var periods: [String]
    var periodId: String?
}

struct DnevnikSlot {
    var lesson: DnevnikLesson
    var replaced: [DnevnikLesson]
}

/// Dnevnik publishes a lesson grid for the whole semester and a dated week grid
/// with the real bell times. A week cell is trusted only after its lesson id was
/// matched against the semester grid, where subgroups are explicit.
enum DnevnikScheduleParser {
    static let school = "53237"
    static let group = "2527502621979585430"
    static let groupName = "ПР126"
    private static let base = "https://schools.dnevnik.ru/v2/r/omsk/schedules/view"

    static func scheduleURL(period: String? = nil, date: Date? = nil) -> String {
        var components = URLComponents(string: base)!
        var items = [
            URLQueryItem(name: "school", value: school),
            URLQueryItem(name: "group", value: group)
        ]
        if let period {
            items.append(URLQueryItem(name: "period", value: period))
        }
        if let date {
            let parts = ScheduleCalendar.calendar.dateComponents([.year, .month, .day], from: date)
            items.append(URLQueryItem(name: "year", value: String(parts.year ?? 0)))
            items.append(URLQueryItem(name: "month", value: String(parts.month ?? 1)))
            items.append(URLQueryItem(name: "day", value: String(parts.day ?? 1)))
        }
        components.queryItems = items
        return components.url!.absoluteString
    }

    static func parse(
        html: String,
        semester: Bool,
        expectedDates: [Date]? = nil,
        period: String? = nil
    ) throws -> DnevnikTable {
        let document = try SwiftSoup.parse(html, base)
        let tables = try document.select("table#editor")
        guard tables.size() == 1, let grid = tables.first() else { throw markup("layout") }
        guard scoped(document) != nil else { throw markup("scope") }

        let dateElements = (try? grid.select("th[id]").array()) ?? []
        var dates: [Date] = []
        for element in dateElements {
            guard let groups = cellDateRegex.first(in: element.id()), let date = date(from: groups) else { continue }
            if !dates.contains(where: { ScheduleCalendar.sameDay($0, date) }) {
                dates.append(date)
            }
        }
        guard !dates.isEmpty else { throw markup("layout") }
        if let expectedDates {
            guard dates.count == expectedDates.count,
                  zip(dates, expectedDates).allSatisfy({ pair in
                      ScheduleCalendar.sameDay(pair.0, pair.1)
                  }) else {
                throw markup("week")
            }
        }
        if !semester {
            guard dates.count == 7 else { throw markup("week") }
            let slotCells = (try? grid.select("td[id]").array()) ?? []
            let slotCount = slotCells.filter { cellSlotRegex.matches($0.id()) }.count
            guard slotCount == dates.count * 12 else { throw markup("week") }
        }

        var periods: [String] = []
        let links = (try? document.select("a[href]").array()) ?? []
        for link in links {
            let text = ((try? link.text()) ?? "").cleanedText
            guard periodLinkRegex.matches(text) else { continue }
            guard let href = try? link.attr("href") else { continue }
            guard let url = scopedURL(href), let value = query(url, "period") else { continue }
            if !periods.contains(value) { periods.append(value) }
        }

        let weekRows = ((try? grid.select("tr[id]").array()) ?? []).filter { $0.id().hasPrefix("week") }
        var weekPeriods: [String] = []
        for row in weekRows {
            let rowID = row.id()
            guard let weekRange = rowID.range(of: "week") else { continue }
            var value = String(rowID[weekRange.upperBound...])
            if let underscore = value.firstIndex(of: "_") {
                value = String(value[..<underscore])
            }
            if !value.isEmpty && !weekPeriods.contains(value) {
                weekPeriods.append(value)
            }
        }
        if weekPeriods.count > 1 { throw markup("period") }
        if !semester, let period, weekPeriods.first != period { throw markup("period") }

        let slotCells = (try? grid.select("td[id]").array()) ?? []
        var lessons: [DnevnikLesson] = []
        for cell in slotCells {
            guard let groups = cellSlotRegex.first(in: cell.id()), groups.count >= 5,
                  let date = date(from: groups),
                  let number = Int(groups[4]), (1...12).contains(number) else {
                throw markup("markup")
            }
            let nodes = cell.children().array().filter { lessonIDRegex.matches($0.id()) }
            let anchorCount = (try? cell.select("a.aL").size()) ?? 0
            guard anchorCount == nodes.count else { throw markup("markup") }
            for node in nodes {
                lessons.append(try lesson(node: node, date: date, number: number, semester: semester))
            }
        }
        let totalAnchors = (try? grid.select("a.aL").size()) ?? 0
        guard totalAnchors == lessons.count else { throw markup("markup") }
        if !semester && lessons.contains(where: { $0.startMinutes == nil || $0.endMinutes == nil }) {
            throw markup("markup")
        }

        return DnevnikTable(
            dates: dates,
            lessons: lessons,
            periods: periods,
            periodId: weekPeriods.first
        )
    }

    static func join(week: DnevnikTable, semester: DnevnikTable) throws -> [Date: [DnevnikSlot]] {
        let index = Dictionary(semester.lessons.map { ($0.id, $0) }) { _, last in last }
        let weekIds = Set(week.lessons.map(\.id))
        for lesson in semester.lessons
        where week.dates.contains(where: { ScheduleCalendar.sameDay($0, lesson.date) }) && !weekIds.contains(lesson.id) {
            throw markup("semester")
        }

        var joined: [DnevnikLesson] = []
        for lesson in week.lessons {
            guard let reference = index[lesson.id] else { throw markup("semester") }
            let same = ScheduleCalendar.sameDay(reference.date, lesson.date)
                && reference.number == lesson.number
                && reference.subject == lesson.subject
                && reference.teacher == lesson.teacher
                && reference.room == lesson.room
                && reference.changed == lesson.changed
                && reference.cancelled == lesson.cancelled
            guard same, reference.subgroup != nil else { throw markup("semester") }
            var copy = lesson
            copy.subgroup = reference.subgroup
            joined.append(copy)
        }

        var result: [Date: [DnevnikSlot]] = [:]
        for date in week.dates {
            let dayLessons = joined.filter { ScheduleCalendar.sameDay($0.date, date) }
            var buckets: [String: [DnevnikLesson]] = [:]
            for lesson in dayLessons {
                let key = "\(lesson.number)|\(lesson.subgroup ?? -1)"
                buckets[key, default: []].append(lesson)
            }

            var slots: [DnevnikSlot] = []
            for bucket in buckets.values {
                let active = bucket.filter { !$0.cancelled }
                if active.count > 1 { throw markup("duplicate") }
                guard let selected = active.first ?? bucket.first else { continue }
                let replaced = bucket.filter { $0.id != selected.id }
                slots.append(DnevnikSlot(lesson: selected, replaced: replaced))
            }

            let mixed = slots.contains { slot in
                !slot.lesson.cancelled && slot.lesson.subgroup == 0 && slots.contains { other in
                    !other.lesson.cancelled
                        && other.lesson.number == slot.lesson.number
                        && other.lesson.id != slot.lesson.id
                }
            }
            if mixed { throw markup("subgroup") }

            slots.sort { $0.lesson.number < $1.lesson.number }
            result[date] = slots
        }
        return result
    }

    // MARK: - Page pieces

    private static func scoped(_ document: Document) -> URL? {
        let headings = (try? document.select("h2").array()) ?? []
        guard let heading = headings.first else { return nil }
        let text = (try? heading.text()) ?? ""
        guard groupWordRegex.matches(text) else { return nil }
        let anchors = (try? heading.select("a[href]").array()) ?? []
        guard let anchor = anchors.first,
              let href = try? anchor.attr("href"),
              let url = scopedURL(href),
              query(url, "class") == group else { return nil }
        return url
    }

    private static func lesson(
        node: Element,
        date: Date,
        number: Int,
        semester: Bool
    ) throws -> DnevnikLesson {
        guard let idGroups = lessonIDRegex.first(in: node.id()), idGroups.count > 1 else {
            throw markup("markup")
        }
        let lessonId = idGroups[1]
        let classNames = (try? node.classNames())?.map { $0 } ?? []
        let classes = Set(classNames)
        guard classes.contains("dL") else { throw markup("markup") }
        guard classes.isSubset(of: allowedClasses) else { throw markup("markup") }
        let changed = classes.contains("dLO")
        let cancelled = classes.contains("dLC")
        if changed && cancelled { throw markup("markup") }

        let anchors = (try? node.select("a.aL[href]").array()) ?? []
        guard anchors.count == 1, let link = anchors.first else { throw markup("markup") }
        let linkText = ((try? link.text()) ?? "").cleanedText
        guard !linkText.isEmpty else { throw markup("markup") }
        let href = (try? link.attr("href")) ?? ""
        guard let url = scopedURL(href),
              query(url, "school") == school,
              query(url, "lesson") == lessonId else { throw markup("scope") }

        let title = ((try? link.attr("title")) ?? "").cleanedText
        let subject = title.isEmpty ? linkText : title
        guard !subject.isEmpty else { throw markup("markup") }
        guard let teacherFull = field(node, "teacher", prefix: "Учитель:") else {
            throw markup("markup")
        }
        let roomValue = field(node, "room", prefix: "Место проведения:")
        let room = roomValue?.caseInsensitiveCompare("Нет кабинета") == .orderedSame ? "" : (roomValue ?? "")
        let timeValue = field(node, "time", prefix: "Время:")
        let (start, end) = time(from: timeValue)
        if !semester && start == nil { throw markup("markup") }

        return DnevnikLesson(
            id: lessonId,
            date: date,
            number: number,
            subgroup: try subgroup(node),
            subject: subject,
            teacher: teacherShort(teacherFull),
            room: room,
            startMinutes: start,
            endMinutes: end,
            changed: changed,
            cancelled: cancelled
        )
    }

    private static func field(_ node: Element, _ id: String, prefix: String) -> String? {
        let elements = (try? node.select("[data-test-id=\(id)]").array()) ?? []
        if elements.count > 1 { return nil }
        guard let element = elements.first else { return nil }
        let title = (try? element.attr("title")) ?? ""
        var value = (title.isEmpty ? ((try? element.text()) ?? "") : title).cleanedText
        if value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.isEmpty ? nil : value
    }

    private static func subgroup(_ node: Element) throws -> Int? {
        let elements = (try? node.select("p[title=\"Кто приходит на урок\"]").array()) ?? []
        let label = (elements.first.flatMap { try? $0.text() } ?? "").cleanedText
        if label.caseInsensitiveCompare("Весь класс") == .orderedSame { return 0 }
        if label.isEmpty { return nil }
        guard let groups = subgroupLabelRegex.first(in: label), groups.count > 1,
              let value = Int(groups[1]) else { throw markup("subgroup_label") }
        return value
    }

    private static func time(from value: String?) -> (Int?, Int?) {
        guard let value,
              let groups = timeRegex.first(in: value), groups.count >= 5,
              let startHour = Int(groups[1]), let startMinute = Int(groups[2]),
              let endHour = Int(groups[3]), let endMinute = Int(groups[4]),
              (0...23).contains(startHour), (0...23).contains(endHour) else { return (nil, nil) }
        return (startHour * 60 + startMinute, endHour * 60 + endMinute)
    }

    private static func teacherShort(_ full: String) -> String {
        let parts = full.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count == 3 else { return full }
        let patronymic = TextRegex("(?:ович|евич|ич|овна|евна|инична)$", options: .caseInsensitive)
        func initial(_ value: String) -> String {
            value.first.map { String($0) + "." } ?? ""
        }
        if patronymic.matches(parts[1]) && !patronymic.matches(parts[2]) {
            return "\(parts[2]) \(initial(parts[0]))\(initial(parts[1]))"
        }
        if patronymic.matches(parts[2]) && !patronymic.matches(parts[1]) {
            return "\(parts[0]) \(initial(parts[1]))\(initial(parts[2]))"
        }
        return full
    }

    private static func scopedURL(_ value: String) -> URL? {
        guard let baseURL = URL(string: base),
              let url = URL(string: value, relativeTo: baseURL)?.absoluteURL else { return nil }
        guard url.scheme == "https",
              url.user == nil,
              url.port == nil || url.port == 443,
              url.host?.lowercased() == "schools.dnevnik.ru" else { return nil }
        return url
    }

    private static func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private static func date(from groups: [String]) -> Date? {
        guard groups.count >= 4,
              let year = Int(groups[1]),
              let month = Int(groups[2]),
              let day = Int(groups[3]) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = ScheduleCalendar.calendar.date(from: components) else { return nil }
        return ScheduleCalendar.startOfDay(date)
    }

    private static func markup(_ code: String) -> DnevnikScheduleError {
        DnevnikScheduleError(code: code, message: "Расписание Дневник.ру изменилось и не распознано")
    }

    private static let cellDateRegex = TextRegex("^d(\\d{4})(\\d{2})(\\d{2})$")
    private static let cellSlotRegex = TextRegex("^d(\\d{4})(\\d{2})(\\d{2})_(\\d{1,2})$")
    private static let lessonIDRegex = TextRegex("^l(\\d+)$")
    private static let subgroupLabelRegex = TextRegex("^Подгруппа\\s+([12])пг$", options: .caseInsensitive)
    private static let timeRegex = TextRegex("^(\\d{2}):(\\d{2})\\s*[-–—]\\s*(\\d{2}):(\\d{2})$")
    private static let periodLinkRegex = TextRegex("семестр|четверть|триместр", options: .caseInsensitive)
    private static let groupWordRegex = TextRegex("(^|\\s)ПР126(\\s|$)")
    private static let allowedClasses: Set<String> = ["dL", "dLO", "dLC"]
}
