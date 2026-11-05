import Foundation

final class ScheduleCache {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Shed", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("schedule-cache.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func read(group: String) -> ScheduleSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              var snapshot = try? decoder.decode(ScheduleSnapshot.self, from: data),
              snapshot.group.caseInsensitiveCompare(group) == .orderedSame else { return nil }
        snapshot.isRefreshing = false
        snapshot.fromCache = true
        snapshot.days = snapshot.days.map { day in
            var normalized = day
            normalized.date = ScheduleCalendar.startOfDay(day.date)
            normalized.lessons = day.lessons.map { lesson in
                var copy = lesson
                copy.subject = SubjectNameNormalizer.expand(copy.subject)
                copy.originalSubject = SubjectNameNormalizer.expand(copy.originalSubject)
                return copy
            }
            return normalized
        }
        return snapshot
    }

    func write(_ snapshot: ScheduleSnapshot) {
        var value = snapshot
        value.isRefreshing = false
        value.fromCache = false
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
