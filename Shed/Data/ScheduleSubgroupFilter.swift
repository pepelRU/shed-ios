import Foundation

enum ScheduleSubgroupFilter {
    static func apply(_ snapshot: ScheduleSnapshot, subgroup: Int) -> ScheduleSnapshot {
        var result = snapshot
        result.days = apply(snapshot.days, subgroup: subgroup)
        result.subgroup = min(max(subgroup, 1), 2)
        return result
    }

    static func apply(_ days: [ScheduleDay], subgroup: Int) -> [ScheduleDay] {
        days.map { day in
            let visible = day.lessons.filter { belongs($0, to: subgroup) }
            var result = day
            result.lessons = visible
            result.hasChanges = visible.contains { $0.changed }
            return result
        }
    }

    private static func belongs(_ lesson: Lesson, to selected: Int) -> Bool {
        guard !lesson.subgroup.isEmpty else { return true }
        guard let groups = subgroupRegex.first(in: lesson.subgroup), groups.count > 1,
              let number = Int(groups[1]) else { return true }
        return number == selected
    }

    private static let subgroupRegex = TextRegex("(?:подгруппа\\s*№?\\s*|№?\\s*)([12])", options: .caseInsensitive)
}
