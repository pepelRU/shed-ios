import Foundation

enum ScheduleDayWindow {
    case today
    case nextDay
    case week
    case nextWeek
}

enum ScheduleDatePolicy {
    static func tomorrowTarget(_ today: Date) -> Date {
        let literalTomorrow = ScheduleCalendar.adding(days: 1, to: today)
        return ScheduleCalendar.isSunday(literalTomorrow)
            ? ScheduleCalendar.adding(days: 1, to: literalTomorrow)
            : literalTomorrow
    }

    static func schoolWeek(_ today: Date, weeksFromCurrent: Int = 0) -> [Date] {
        let monday = ScheduleCalendar.weekStart(today)
        let shifted = ScheduleCalendar.calendar.date(byAdding: .weekOfYear, value: weeksFromCurrent, to: monday) ?? monday
        return (0...5).map { ScheduleCalendar.adding(days: $0, to: shifted) }
    }

    static func actualDay(today: Date, todayEnded: Bool) -> Date {
        if todayEnded || ScheduleCalendar.isSunday(today) {
            return tomorrowTarget(today)
        }
        return today
    }

    static func dayEnd(_ lessons: [Lesson]) -> Int? {
        lessons.map(\.endMinutes).max()
    }

    static func isDayEnded(date: Date, lessons: [Lesson], now: Date) -> Bool {
        guard let end = dayEnd(lessons) else { return false }
        let endDate = ScheduleCalendar.date(on: date, minutes: end)
        return now >= endDate
    }

    static func actualDayFor(today: Date, todayDay: ScheduleDay?, now: Date) -> Date {
        actualDay(today: today, todayEnded: isDayEnded(date: today, lessons: todayDay?.lessons ?? [], now: now))
    }

    static func relativeDayOffset(date: Date, today: Date) -> Int? {
        let distance = ScheduleCalendar.dayDistance(from: today, to: date)
        return (0...2).contains(distance) ? distance : nil
    }

    static func windowDates(
        window: ScheduleDayWindow,
        today: Date,
        todayDay: ScheduleDay?,
        now: Date
    ) -> [Date] {
        let actual = actualDayFor(today: today, todayDay: todayDay, now: now)
        switch window {
        case .today:
            return [actual]
        case .nextDay:
            return [tomorrowTarget(actual)]
        case .week:
            // The week tab shows the whole week. Past days stay visible but muted,
            // so the list never looks empty after the first pair.
            return schoolWeek(actual)
        case .nextWeek:
            return schoolWeek(actual, weeksFromCurrent: 1)
        }
    }

    static func actualDays(_ days: [Date], actualDay: Date) -> [Date] {
        let filtered = days.filter { ScheduleCalendar.startOfDay($0) >= ScheduleCalendar.startOfDay(actualDay) }
        return filtered.isEmpty ? days : filtered
    }

    static func loadingWindow(today: Date) -> [Date] {
        schoolWeek(today) + schoolWeek(today, weeksFromCurrent: 1)
    }

    static func changesWindow(today: Date, period: ScheduleRefreshPeriod = .todayAndTomorrow) -> [Date] {
        switch period {
        case .todayAndTomorrow:
            return [today, ScheduleCalendar.adding(days: 1, to: today)]
                .filter { !ScheduleCalendar.isSunday($0) }
        case .currentWeek:
            return schoolWeek(today)
        case .twoWeeks:
            return loadingWindow(today: today)
        }
    }
}
