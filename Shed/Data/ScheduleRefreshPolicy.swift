import Foundation

// Rebuild the display weeks without erasing verified changes outside today's check window.
enum ScheduleRefreshPolicy {
    static func refreshedScheduleDays(
        today: Date,
        group: String,
        previousDays: [ScheduleDay],
        changesByDate: [Date: ScheduleChangeSet],
        checkedAt: Date,
        checkedDates: Set<Date>? = nil
    ) -> [ScheduleDay] {
        let checked = checkedDates ?? Set(ScheduleDatePolicy.changesWindow(today: today))
        let previous = Dictionary(
            previousDays
                .filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }
                .map { (ScheduleCalendar.startOfDay($0.date), $0) },
            uniquingKeysWith: { _, last in last }
        )

        return ScheduleDatePolicy.loadingWindow(today: today).map { date in
            let key = ScheduleCalendar.startOfDay(date)
            if !checked.contains(key) {
                if let cached = previous[key], cached.hasChanges || cached.lessons.contains(where: { $0.changed }) {
                    return cached
                }
                return LocalBaseSchedule.day(for: date, group: group, updatedAt: previous[key]?.lastUpdated)
            }

            let base = LocalBaseSchedule.day(for: date, group: group, updatedAt: checkedAt)
            let changes = changesByDate[key]
            let lessons = changes.map { ScheduleMerger.merge(base: base.lessons, changes: $0) } ?? base.lessons
            let hasChanges = changes != nil && (!(changes?.lessons.isEmpty ?? true)
                || !(changes?.bellTimes.isEmpty ?? true)
                || lessons.contains(where: { $0.changed }))
            return ScheduleDay(
                date: base.date,
                group: group,
                lessons: lessons,
                hasChanges: hasChanges,
                lastUpdated: checkedAt,
                academicWeek: base.academicWeek
            )
        }
    }
}
