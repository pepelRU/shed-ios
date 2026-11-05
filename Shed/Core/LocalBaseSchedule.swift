import Foundation

/// Permanent two-week timetable for ПР126, Ленина 24.
/// The college publishes changes separately; this is the trusted base copy.
enum LocalBaseSchedule {
    static func day(for date: Date, group: String, updatedAt: Date? = nil) -> ScheduleDay {
        let normalized = ScheduleCalendar.startOfDay(date)
        let dayOfWeek = ScheduleCalendar.weekday(normalized)
        let week = weekNumber(for: normalized)
        let lessons: [Lesson]
        if dayOfWeek == 1 {
            lessons = []
        } else {
            lessons = (rows["\(week)-\(dayOfWeek)"] ?? []).compactMap(lesson(from:))
        }
        return ScheduleDay(
            date: normalized,
            group: group,
            lessons: lessons,
            hasChanges: false,
            lastUpdated: updatedAt,
            academicWeek: week
        )
    }

    static func weekNumber(for date: Date) -> Int {
        let calendar = ScheduleCalendar.calendar
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return 1 }
        let academicYear = month >= 9 ? year : year - 1
        var september = DateComponents()
        september.year = academicYear
        september.month = 9
        september.day = 1
        guard let firstOfSeptember = calendar.date(from: september) else { return 1 }
        let weekday = calendar.component(.weekday, from: firstOfSeptember)
        let offset = (weekday + 5) % 7
        guard let anchor = calendar.date(byAdding: .day, value: -offset, to: firstOfSeptember) else { return 1 }
        let days = calendar.dateComponents([.day], from: anchor, to: ScheduleCalendar.startOfDay(date)).day ?? 0
        let weeks = days / 7
        return abs(weeks) % 2 + 1
    }

    private static func lesson(from raw: String) -> Lesson? {
        let fields = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 6,
              let number = Int(fields[0]),
              let start = Lesson.minutes(from: fields[1]),
              let end = Lesson.minutes(from: fields[2]) else { return nil }
        return Lesson(
            number: number,
            startMinutes: start,
            endMinutes: end,
            subject: fields[3],
            teacher: fields[4],
            room: fields[5],
            subgroup: fields.count > 6 ? fields[6] : ""
        )
    }

    private static let rows: [String: [String]] = [
        "1-2": [
            "1|08:00|09:30|Биология|Закутаева Н.В.|506|",
            "2|09:40|11:10|Основы безопасности и защиты Родины|Иванович М.А.|505|",
            "3|11:30|13:00|История|Арефьева Т.Г.|329|",
            "4|13:40|15:10|Разговоры о важном|Жаворонкова Я.В.|328|"
        ],
        "1-3": [
            "1|08:00|09:30|Русский язык|Чалимов А.М.|120|",
            "2|09:40|11:10|Математика|Колесникова А.А.|507|",
            "3|11:30|13:00|Физика|Сабитова А.В.|123|"
        ],
        "1-4": [
            "1|08:00|09:30|Математика|Колесникова А.А.|507|",
            "2|09:40|11:10|Физическая культура|Урванцев А.Е.|401|",
            "3|11:30|13:00|Иностранный язык|Антонова О.Н.|403|Подгруппа 1",
            "3|11:30|13:00|Иностранный язык|Передрей А.Е.|204|Подгруппа 2"
        ],
        "1-5": [
            "1|08:00|09:30|Обществознание|Жаворонкова Я.В.|328|",
            "2|09:40|11:10|Математика|Колесникова А.А.|507|",
            "3|11:30|13:00|Информатика|Фадеева Е.Н.|210|"
        ],
        "1-6": [
            "1|08:00|09:30|Литература|Чалимов А.М.|120|",
            "2|09:40|11:10|География|Аубакирова С.Ш.|203|",
            "3|11:30|13:00|Математика|Колесникова А.А.|507|"
        ],
        "1-7": [
            "1|08:00|09:30|Информатика+|Фадеева Е.Н.|220+|Подгруппа 1",
            "1|08:00|09:30|Информатика+|Бураева А.А.|220+|Подгруппа 2",
            "2|09:40|11:10|История|Арефьева Т.Г.|329|",
            "3|11:30|13:00|Химия|Краснова Т.В.|325|"
        ],
        "2-2": [
            "1|08:00|09:30|Иностранный язык|Антонова О.Н.|403|Подгруппа 1",
            "1|08:00|09:30|Иностранный язык|Передрей А.Е.|204|Подгруппа 2",
            "2|09:40|11:10|Информатика+|Фадеева Е.Н.|220+|Подгруппа 1",
            "2|09:40|11:10|Информатика+|Бураева А.А.|220+|Подгруппа 2",
            "3|11:30|13:00|Математика|Колесникова А.А.|507|",
            "4|13:40|15:10|Разговоры о важном|Жаворонкова Я.В.|328|"
        ],
        "2-3": [
            "1|08:00|09:30|Математика|Колесникова А.А.|507|",
            "2|09:40|11:10|Биология|Закутаева Н.В.|506|",
            "3|11:30|13:00|Русский язык|Чалимов А.М.|120|"
        ],
        "2-4": [
            "1|08:00|09:30|Обществознание|Жаворонкова Я.В.|328|",
            "2|09:40|11:10|Математика|Колесникова А.А.|507|",
            "3|11:30|13:00|Физическая культура|Урванцев А.Е.|401|"
        ],
        "2-5": [
            "1|08:00|09:30|Основы безопасности и защиты Родины|Иванович М.А.|505|",
            "2|09:40|11:10|Информатика|Фадеева Е.Н.|210|",
            "3|11:30|13:00|Литература|Чалимов А.М.|120|"
        ],
        "2-6": [
            "1|08:00|09:30|История|Арефьева Т.Г.|329|",
            "2|09:40|11:10|География|Аубакирова С.Ш.|203|",
            "3|11:30|13:00|Литература|Чалимов А.М.|120|"
        ],
        "2-7": [
            "1|08:00|09:30|Физика|Сабитова А.В.|123|",
            "2|09:40|11:10|Химия|Краснова Т.В.|325|",
            "3|11:30|13:00|Индивидуальный проект|Галыгина А.В.|212+|"
        ]
    ]
}
