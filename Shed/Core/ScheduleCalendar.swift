import Foundation

enum ScheduleCalendar {
    static let timeZone = TimeZone(identifier: "Asia/Omsk") ?? TimeZone.current

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        value.locale = Locale(identifier: "ru_RU")
        value.firstWeekday = 2
        return value
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func today() -> Date {
        startOfDay(Date())
    }

    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: startOfDay(date)) ?? date
    }

    static func adding(weeks: Int, to date: Date) -> Date {
        calendar.date(byAdding: .weekOfYear, value: weeks, to: date) ?? date
    }

    static func sameDay(_ first: Date, _ second: Date) -> Bool {
        calendar.isDate(first, inSameDayAs: second)
    }

    static func weekday(_ date: Date) -> Int {
        // 1 = Sunday ... 7 = Saturday, same as Android's DayOfWeek mapping.
        calendar.component(.weekday, from: date)
    }

    static func isSunday(_ date: Date) -> Bool {
        weekday(date) == 1
    }

    static func weekStart(_ date: Date) -> Date {
        let value = startOfDay(date)
        let offset = (weekday(value) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: value) ?? value
    }

    static func minutesOfDay(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func date(on day: Date, minutes: Int) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: startOfDay(day)) ?? day
    }

    static func dayDistance(from first: Date, to second: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(first), to: startOfDay(second)).day ?? 0
    }
}

enum DateFormatters {
    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = ScheduleCalendar.timeZone
        formatter.calendar = ScheduleCalendar.calendar
        formatter.isLenient = false
        return formatter
    }

    static let siteDate = make("dd.MM.yyyy")
    static let fullDate = make("dd.MM.yyyy")
    static let dayMonth = make("dd.MM")
    static let humanDate = make("d MMMM")
    static let weekdayFull = make("EEEE")
    static let weekdayShort = make("EE")
    static let time = make("HH:mm")
    static let updated = make("dd.MM, HH:mm")
}

extension String {
    var cleanedText: String {
        replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var collapsedUpper: String {
        cleanedText.uppercased().replacingOccurrences(of: " ", with: "")
    }

    func deletingSpaces() -> String {
        replacingOccurrences(of: " ", with: "")
    }
}

struct TextRegex {
    private let expression: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        // All patterns are compile-time constants in this project.
        expression = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func groups(in string: String) -> [[String]] {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.matches(in: string, options: [], range: range).compactMap { match in
            (0..<match.numberOfRanges).map { index in
                guard let resultRange = Range(match.range(at: index), in: string) else { return "" }
                return String(string[resultRange])
            }
        }
    }

    func first(in string: String) -> [String]? {
        groups(in: string).first
    }

    func matches(_ string: String) -> Bool {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.firstMatch(in: string, options: [], range: range) != nil
    }

    func matchesEntire(_ string: String) -> Bool {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = expression.firstMatch(in: string, options: [], range: range) else { return false }
        return match.range == range
    }

    func replacing(in string: String, with template: String) -> String {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: template)
    }
}
