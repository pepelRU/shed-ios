import Foundation
import SwiftSoup

/// Parses the published changes pages of oat.ru.
struct ScheduleHtmlParser {
    func parseChanges(html: String, date: Date, group: String) throws -> ScheduleChangeSet {
        let document = try SwiftSoup.parse(html)
        let main = try document.select("main").first()
        let pageText = (try? main?.text()) ?? ""
        let available = !pageText.localizedCaseInsensitiveContains("Не удалось получить изменения")
        let academicWeek = academicWeekRegex.first(in: pageText).flatMap { groups -> Int? in
            groups.count > 1 ? Int(groups[1]) : nil
        }

        var availableDates: Set<Date> = []
        let anchors = (try? document.select("a[href]").array()) ?? []
        for anchor in anchors {
            let href = (try? anchor.attr("href")) ?? ""
            guard href.contains("/timetable/Changes/") else { continue }
            let text = (try? anchor.text()) ?? ""
            if let parsed = DateFormatters.siteDate.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                availableDates.insert(ScheduleCalendar.startOfDay(parsed))
            }
        }

        let activeText = (try? document.select("a.choose-item.active").first()?.text()) ?? ""
        let resolvedDate = DateFormatters.siteDate.date(from: activeText.trimmingCharacters(in: .whitespacesAndNewlines))
            .map(ScheduleCalendar.startOfDay) ?? ScheduleCalendar.startOfDay(date)

        let tables = (try? document.select("table").array()) ?? []
        let bellTable = tables.first { table in
            ((try? table.select("th").text()) ?? "").localizedCaseInsensitiveContains("Режим звонков")
        }
        let bellTimes = parseBellTimes(bellTable)

        let lessons = available ? parseChangeLessons(main: main, group: group, bellTimes: bellTimes) : []
        return ScheduleChangeSet(
            date: resolvedDate,
            academicWeek: academicWeek,
            availableDates: availableDates,
            bellTimes: bellTimes,
            lessons: lessons,
            available: available
        )
    }

    // MARK: - Bell times

    private func parseBellTimes(_ table: Element?) -> [Int: BellTime] {
        guard let table else { return [:] }
        let rows = (try? table.select("tbody tr").array()) ?? []
        var result: [Int: BellTime] = [:]
        for row in rows {
            let cells = (try? row.select("td").array()) ?? []
            guard let first = cells.first else { continue }
            let numberText = ((try? first.text()) ?? "").cleanedText
            guard let number = Int(numberText) else { continue }
            let rowText = (try? row.text()) ?? ""
            let times = timeRegex.groups(in: rowText).compactMap { groups in
                groups.first.flatMap(Lesson.minutes(from:))
            }
            if times.count >= 2 {
                result[number] = BellTime(start: times[0], end: times[1])
            }
        }
        return result
    }

    // MARK: - Lessons

    private func parseChangeLessons(main: Element?, group: String, bellTimes: [Int: BellTime]) -> [Lesson] {
        guard let main else { return [] }
        let tables = (try? main.select("table").array()) ?? []
        var seen = Set<String>()
        var lessons: [Lesson] = []
        for table in tables {
            let headings = (try? table.select("th").text()) ?? ""
            if headings.localizedCaseInsensitiveContains("Режим звонков") { continue }
            for lesson in parseChangeTable(table, group: group, bellTimes: bellTimes) {
                let key = "\(lesson.number)|\(lesson.subgroup)|\(lesson.subject)|\(lesson.teacher)|\(lesson.room)|\(lesson.cancelled)"
                if seen.insert(key).inserted {
                    lessons.append(lesson)
                }
            }
        }
        return lessons.sorted {
            if $0.number != $1.number { return $0.number < $1.number }
            return $0.subgroup < $1.subgroup
        }
    }

    private func parseChangeTable(_ table: Element, group: String, bellTimes: [Int: BellTime]) -> [Lesson] {
        let headerElements = (try? table.select("thead th").array()) ?? []
        let headers = headerElements.map { ((try? $0.text()) ?? "").cleanedText }
        let groupIndex = headers.firstIndex { $0.caseInsensitiveCompare("Группа") == .orderedSame } ?? -1
        let pairIndexes = headers.indices.filter { headers[$0].caseInsensitiveCompare("Пара") == .orderedSame }
        let roomIndexes = headers.indices.filter { headers[$0].lowercased().hasPrefix("аудит") }
        let subjectIndexes = headers.indices.filter { headers[$0].lowercased().contains("дисциплин") }
        let teacherIndexes = headers.indices.filter { headers[$0].lowercased().contains("преподавател") }
        let reasonIndex = headers.firstIndex { $0.lowercased().contains("причин") } ?? -1
        let structured = groupIndex >= 0 && pairIndexes.count >= 2 && subjectIndexes.count >= 2

        let normalizedGroup = group.collapsedUpper
        let rows = (try? table.select("tbody tr").array()) ?? []
        var result: [Lesson] = []
        for row in rows {
            let rowText = ((try? row.text()) ?? "").cleanedText
            guard rowText.collapsedUpper.contains(normalizedGroup) else { continue }
            let cells = (try? row.select("td").array()) ?? []
            if structured {
                if let lesson = parseStructuredRow(
                    row: row,
                    cells: cells,
                    groupIndex: groupIndex,
                    pairIndexes: pairIndexes,
                    roomIndexes: roomIndexes,
                    subjectIndexes: subjectIndexes,
                    teacherIndexes: teacherIndexes,
                    reasonIndex: reasonIndex,
                    group: group,
                    bellTimes: bellTimes
                ) {
                    result.append(lesson)
                }
            } else if let lesson = parseSimpleRow(row: row, cells: cells, group: group, bellTimes: bellTimes) {
                result.append(lesson)
            }
        }
        return result
    }

    private func parseStructuredRow(
        row: Element,
        cells: [Element],
        groupIndex: Int,
        pairIndexes: [Int],
        roomIndexes: [Int],
        subjectIndexes: [Int],
        teacherIndexes: [Int],
        reasonIndex: Int,
        group: String,
        bellTimes: [Int: BellTime]
    ) -> Lesson? {
        func value(_ index: Int?) -> String {
            guard let index, index >= 0, index < cells.count else { return "" }
            return ((try? cells[index].text()) ?? "").cleanedText
        }

        guard value(groupIndex).collapsedUpper.contains(group.collapsedUpper) else { return nil }

        let oldNumber = Int(value(pairIndexes.first))
        let newNumber = Int(value(pairIndexes.last))
        guard let finalNumber = newNumber ?? oldNumber else { return nil }
        guard let times = bellTimes[finalNumber] ?? oldNumber.flatMap({ bellTimes[$0] }) else { return nil }

        let oldRoom = value(roomIndexes.first)
        let newRoom = value(roomIndexes.last)
        let oldSubject = SubjectNameNormalizer.expand(value(subjectIndexes.first))
        let newSubject = SubjectNameNormalizer.expand(value(subjectIndexes.last))
        let oldTeacher = value(teacherIndexes.first)
        let newTeacher = value(teacherIndexes.last)
        let reason = value(reasonIndex)

        let oldHalfEmpty = oldNumber == nil && oldRoom.isEmpty && oldSubject.isEmpty && oldTeacher.isEmpty
        let newHalfEmpty = newNumber == nil && newRoom.isEmpty && newSubject.isEmpty && newTeacher.isEmpty
        let added = oldHalfEmpty && !newHalfEmpty
        let cancelled = !added && (reason.localizedCaseInsensitiveContains("отмен") || newHalfEmpty)

        var kinds: Set<LessonChangeKind> = []
        if added { kinds.insert(.added) }
        if cancelled { kinds.insert(.cancelled) }
        if !cancelled {
            if !newSubject.isEmpty && newSubject != oldSubject { kinds.insert(.subject) }
            if !newTeacher.isEmpty && newTeacher != oldTeacher { kinds.insert(.teacher) }
            if !newRoom.isEmpty && newRoom != oldRoom { kinds.insert(.room) }
            if let newNumber, newNumber != oldNumber { kinds.insert(.time) }
        }

        return Lesson(
            number: finalNumber,
            startMinutes: times.start,
            endMinutes: times.end,
            subject: newSubject.isEmpty ? oldSubject : newSubject,
            teacher: newTeacher.isEmpty ? oldTeacher : newTeacher,
            room: newRoom.isEmpty ? oldRoom : newRoom,
            originalNumber: oldNumber,
            originalSubject: oldSubject,
            originalTeacher: oldTeacher,
            originalRoom: oldRoom,
            cancelled: cancelled,
            changed: true,
            changeKinds: kinds
        )
    }

    private func parseSimpleRow(
        row: Element,
        cells: [Element],
        group: String,
        bellTimes: [Int: BellTime]
    ) -> Lesson? {
        let fields = cells
            .map { ((try? $0.text()) ?? "").cleanedText }
            .filter { !$0.isEmpty }
        guard !fields.isEmpty else { return nil }
        let raw = fields.joined(separator: " ")

        var number: Int?
        for field in fields {
            if let groups = lessonNumberRegex.first(in: field), groups.count > 1, let value = Int(groups[1]) {
                number = value
                break
            }
        }
        guard let number else { return nil }

        let explicitTimes = timeRegex.groups(in: raw).compactMap { groups in
            groups.first.flatMap(Lesson.minutes(from:))
        }
        let times: BellTime
        if explicitTimes.count >= 2 {
            times = BellTime(start: explicitTimes[0], end: explicitTimes[1])
        } else if let bell = bellTimes[number] {
            times = bell
        } else {
            return nil
        }

        let cancelledByText = raw.localizedCaseInsensitiveContains("отмен")
        let cancelledByClass = ((try? row.select(".cancelled, .canceled").isEmpty()) ?? true) == false
        let cancelled = cancelledByText || cancelledByClass

        let subgroup = fields.first { $0.lowercased().hasPrefix("подгруппа") } ?? ""
        let teacher = fields.first { teacherRegex.matches($0) } ?? ""
        let room = fields.reversed().first { field in
            roomRegex.matchesEntire(field) && !timeRegex.matches(field)
        } ?? ""

        let subject = fields.first { field in
            let normalized = field.collapsedUpper
            return normalized != group.collapsedUpper
                && field != subgroup
                && field != teacher
                && field != room
                && !timeRegex.matches(field)
                && !lessonNumberRegex.matches(field)
                && !field.localizedCaseInsensitiveContains("замен")
                && !field.localizedCaseInsensitiveContains("отмен")
        } ?? ""

        return Lesson(
            number: number,
            startMinutes: times.start,
            endMinutes: times.end,
            subject: SubjectNameNormalizer.expand(subject),
            teacher: teacher,
            room: room,
            subgroup: subgroup,
            cancelled: cancelled,
            changed: true,
            changeKinds: cancelled ? [.cancelled] : []
        )
    }

    // MARK: - Regexes

    private let academicWeekRegex = TextRegex("([12])\\s+учебн(?:ая|ой)\\s+недел", options: .caseInsensitive)
    private let timeRegex = TextRegex("(?:[01]?\\d|2[0-3]):[0-5]\\d")
    private let lessonNumberRegex = TextRegex("^\\s*(?:№\\s*)?([1-9]|10)(?:\\s*(?:пара|урок))?\\s*$", options: .caseInsensitive)
    private let teacherRegex = TextRegex("[А-ЯЁ][а-яё-]+\\s+[А-ЯЁ]\\.\\s*[А-ЯЁ]\\.", options: [])
    private let roomRegex = TextRegex("(?:каб(?:инет)?\\.?\\s*)?[А-ЯA-Z]?\\d{2,4}[А-ЯA-Z+/-]*", options: .caseInsensitive)
}
