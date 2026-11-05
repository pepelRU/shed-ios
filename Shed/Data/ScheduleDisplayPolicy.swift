import Foundation

enum ScheduleDisplayPolicy {
    /// College change pages sometimes write the cancellation into the subject cell.
    static func hideCancelled(_ day: ScheduleDay) -> ScheduleDay {
        let visible = day.lessons.filter { !isCancelled($0) }
        guard visible.count != day.lessons.count else { return day }
        var result = day
        result.lessons = visible
        result.hasChanges = visible.contains { $0.changed }
        return result
    }

    static func isCancelled(_ lesson: Lesson) -> Bool {
        lesson.cancelled || lesson.subject.localizedCaseInsensitiveContains("отмен")
    }
}
