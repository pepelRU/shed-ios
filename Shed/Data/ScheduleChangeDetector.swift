import Foundation

enum ScheduleChangeDetector {
    static func detect(oldDays: [ScheduleDay], newDays: [ScheduleDay], today: Date) -> ScheduleChangeSummary {
        guard !oldDays.isEmpty else { return .empty }
        let oldByDate = Dictionary(
            oldDays.map { (ScheduleCalendar.startOfDay($0.date), $0) },
            uniquingKeysWith: { _, last in last }
        )
        let normalizedToday = ScheduleCalendar.startOfDay(today)
        var lines: [String] = []

        for newDay in newDays where ScheduleCalendar.startOfDay(newDay.date) >= normalizedToday {
            guard let oldDay = oldByDate[ScheduleCalendar.startOfDay(newDay.date)] else { continue }
            let oldLessons = Dictionary(oldDay.lessons.map { ($0.stableKey, $0) }) { _, last in last }
            let newLessons = Dictionary(newDay.lessons.map { ($0.stableKey, $0) }) { _, last in last }
            let date = DateFormatters.dayMonth.string(from: newDay.date)

            for (key, current) in newLessons {
                let originalKey = current.originalNumber.map { "\($0)|\(current.subgroup.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())" }
                let previous = oldLessons[key] ?? originalKey.flatMap { oldLessons[$0] }
                switch previous {
                case nil:
                    lines.append("\(date) · добавлена \(current.number)-я пара: \(current.subject)")
                case let previous? where !previous.cancelled && current.cancelled:
                    lines.append("\(date) · отменена \(current.number)-я пара: \(previous.subject)")
                case let previous? where previous.subject != current.subject:
                    lines.append("\(date) · \(current.number)-я пара: \(current.subject)")
                case let previous? where previous.teacher != current.teacher:
                    lines.append("\(date) · сменился преподаватель на \(current.number)-й паре")
                case let previous? where previous.startMinutes != current.startMinutes || previous.endMinutes != current.endMinutes:
                    lines.append("\(date) · изменено время \(current.number)-й пары")
                default:
                    break
                }
            }

            for (key, lesson) in oldLessons where newLessons[key] == nil && lesson.changeKinds.contains(.added) {
                lines.append("\(date) · убрана добавленная \(lesson.number)-я пара: \(lesson.subject)")
            }
        }

        var seen = Set<String>()
        let unique = lines.filter { seen.insert($0).inserted }
        return ScheduleChangeSummary(lines: Array(unique.prefix(5)))
    }
}
