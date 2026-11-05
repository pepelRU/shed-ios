import Foundation

enum ScheduleMerger {
    static func merge(base: [Lesson], changes: ScheduleChangeSet) -> [Lesson] {
        var result = base.map { lesson in
            guard let times = changes.bellTimes[lesson.number],
                  times.start != lesson.startMinutes || times.end != lesson.endMinutes else { return lesson }
            var changed = lesson
            changed.startMinutes = times.start
            changed.endMinutes = times.end
            return changed
        }

        for incoming in changes.lessons {
            let matchingIndexes: [Int]
            if incoming.changeKinds.contains(.added) {
                matchingIndexes = []
            } else {
                matchingIndexes = result.indices.filter { matches(original: incoming, current: result[$0]) }
            }

            if matchingIndexes.isEmpty {
                var added = incoming
                added.changed = true
                added.changeKinds.insert(.added)
                result.append(added)
                continue
            }

            for index in matchingIndexes {
                let current = result[index]
                if incoming.cancelled {
                    var cancelled = current
                    cancelled.cancelled = true
                    cancelled.changed = true
                    cancelled.changeKinds.insert(.cancelled)
                    result[index] = cancelled
                } else {
                    var kinds: Set<LessonChangeKind> = []
                    if !incoming.subject.isEmpty && incoming.subject != current.subject { kinds.insert(.subject) }
                    if !incoming.teacher.isEmpty && incoming.teacher != current.teacher { kinds.insert(.teacher) }
                    if !incoming.room.isEmpty && incoming.room != current.room { kinds.insert(.room) }
                    if incoming.startMinutes != current.startMinutes || incoming.endMinutes != current.endMinutes { kinds.insert(.time) }

                    var updated = current
                    updated.number = incoming.number
                    updated.startMinutes = incoming.startMinutes
                    updated.endMinutes = incoming.endMinutes
                    updated.subject = incoming.subject.isEmpty ? current.subject : incoming.subject
                    updated.teacher = incoming.teacher.isEmpty ? current.teacher : incoming.teacher
                    updated.room = incoming.room.isEmpty ? current.room : incoming.room
                    updated.subgroup = incoming.subgroup.isEmpty ? current.subgroup : incoming.subgroup
                    updated.originalNumber = incoming.originalNumber
                    updated.originalSubject = incoming.originalSubject
                    updated.originalTeacher = incoming.originalTeacher
                    updated.originalRoom = incoming.originalRoom
                    updated.changed = !kinds.isEmpty || current.changed
                    updated.changeKinds.formUnion(kinds)
                    result[index] = updated
                }
            }
        }

        return result.sorted {
            if $0.number != $1.number { return $0.number < $1.number }
            return $0.subgroup < $1.subgroup
        }
    }

    private static func matches(original incoming: Lesson, current: Lesson) -> Bool {
        if current.number != (incoming.originalNumber ?? incoming.number) { return false }
        if !incoming.subgroup.isEmpty && current.subgroup.caseInsensitiveCompare(incoming.subgroup) != .orderedSame { return false }
        if !incoming.originalSubject.isEmpty && current.subject.caseInsensitiveCompare(incoming.originalSubject) != .orderedSame { return false }
        if !incoming.originalTeacher.isEmpty && current.teacher.caseInsensitiveCompare(incoming.originalTeacher) != .orderedSame { return false }
        if !incoming.originalRoom.isEmpty && current.room.caseInsensitiveCompare(incoming.originalRoom) != .orderedSame { return false }
        return true
    }
}
