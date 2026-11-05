import Foundation

/// Expands the compact labels used by oat.ru into readable subject names.
enum SubjectNameNormalizer {
    static func expand(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPracticeMark = cleaned.hasSuffix("+")
        let baseName = hasPracticeMark ? String(cleaned.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
        let expanded = expansions[key(baseName)] ?? baseName
        return hasPracticeMark ? expanded + "+" : expanded
    }

    private static func key(_ value: String) -> String {
        let allowed = Set("АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String(value.uppercased().filter { allowed.contains($0) })
    }

    private static let expansions: [String: String] = [
        "БИОЛОГ": "Биология",
        "ГЕОГРАФ": "География",
        "ИНФОРМ": "Информатика",
        "ИНЯЗЫК": "Иностранный язык",
        "ЛИТЕРАТ": "Литература",
        "МАТЕМ": "Математика",
        "ОБЗР": "Основы безопасности и защиты Родины",
        "ОБЩЕСТВ": "Обществознание",
        "ПРОЕКТ": "Индивидуальный проект",
        "РАЗГОВО": "Разговоры о важном",
        "РУСЯЗ": "Русский язык",
        "ФИЗРА": "Физическая культура"
    ]
}
