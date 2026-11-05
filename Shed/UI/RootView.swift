import SwiftUI

enum ScheduleMode: String, CaseIterable, Identifiable {
    case today
    case tomorrow
    case week
    case nextWeek

    var id: String { rawValue }

    var window: ScheduleDayWindow {
        switch self {
        case .today: return .today
        case .tomorrow: return .nextDay
        case .week: return .week
        case .nextWeek: return .nextWeek
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var repository: ScheduleRepository
    @EnvironmentObject private var preferences: SchedulePreferences
    @Environment(\.scenePhase) private var scenePhase

    @State private var mode: ScheduleMode = .today
    @State private var showSettings = false
    @State private var detailsDay: ScheduleDay?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            content(now: timeline.date)
        }
        .background(ShedColors.background.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(preferences)
                .environmentObject(repository)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $detailsDay) { day in
            ChangesDialog(day: day)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await repository.refreshBaseIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                if let checked = repository.snapshot.changesCheckedAt,
                   Date().timeIntervalSince(checked) < 10 * 60 {
                    return
                }
                await repository.refresh()
            }
        }
    }

    private func content(now: Date) -> some View {
        let snapshot = repository.snapshot
        let today = ScheduleCalendar.startOfDay(now)
        let todayDay = resolveDay(snapshot, today)
        let actualDay = ScheduleDatePolicy.actualDayFor(today: today, todayDay: todayDay, now: now)
        let dates = ScheduleDatePolicy.windowDates(
            window: mode.window,
            today: today,
            todayDay: todayDay,
            now: now
        )

        return VStack(spacing: 0) {
            header(dates: dates, today: today)
            modePicker(actualDay: actualDay, today: today)
            freshness(snapshot)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if dates.isEmpty {
                        emptyState("Расписание недоступно")
                    } else if mode == .today || mode == .tomorrow {
                        if let day = resolveDay(snapshot, dates[0]) {
                            dayContent(
                                day,
                                now: now,
                                compact: false,
                                showBreaks: mode == .today && ScheduleCalendar.sameDay(day.date, today)
                            )
                        } else {
                            emptyState("Расписание недоступно")
                        }
                    } else {
                        ForEach(dates, id: \.self) { date in
                            if let day = resolveDay(snapshot, date) {
                                weekHeader(day, today: today)
                                dayContent(day, now: now, compact: true, showBreaks: false)
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .refreshable {
                await repository.refresh()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    // MARK: - Header

    private func header(dates: [Date], today: Date) -> some View {
        let first = dates.first ?? today
        let title: String
        if mode == .week || mode == .nextWeek, let last = dates.last {
            title = "\(DateFormatters.dayMonth.string(from: first)) — \(DateFormatters.dayMonth.string(from: last))"
        } else {
            title = DateFormatters.humanDate.string(from: first)
        }
        let isWeekMode = mode == .week || mode == .nextWeek
        let eyebrow = (isWeekMode ? weekEyebrow(dates: dates, today: today) : nil) ?? weekdayTitle(first)

        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.medium))
                    .tracking(1.2)
                    .foregroundStyle(ShedColors.muted)
                Text(title)
                    .font(.system(size: 30, weight: .black))
                    .tracking(-0.6)
                    .foregroundStyle(ShedColors.text)
            }
            Spacer()
            Button {
                Haptics.tick()
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ShedColors.text)
                    .frame(width: 42, height: 42)
                    .background(ShedColors.surfaceVariant, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func modePicker(actualDay: Date, today: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(ScheduleMode.allCases) { item in
                let selected = item == mode
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        mode = item
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tabTitle(item, actualDay: actualDay, today: today))
                            .font(.system(size: 12, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? ShedColors.primary : ShedColors.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Capsule()
                            .fill(selected ? ShedColors.primary : Color.clear)
                            .frame(width: 28, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 42)
    }

    // MARK: - Freshness

    private func freshness(_ snapshot: ScheduleSnapshot) -> some View {
        let failed = snapshot.changesCheckFailed
        let text: String
        if snapshot.isRefreshing {
            text = "Проверяю изменения…"
        } else if failed, let checked = snapshot.changesCheckedAt {
            text = "Изменения не проверены, показаны данные от \(DateFormatters.updated.string(from: checked)). \(snapshot.errorMessage ?? "")"
        } else if failed {
            text = "Изменения не проверены, показано основное расписание. \(snapshot.errorMessage ?? "")"
        } else if let checked = snapshot.changesCheckedAt {
            text = "Изменения проверены \(DateFormatters.updated.string(from: checked))"
        } else {
            text = "Изменения ещё не проверены · потяни вниз"
        }
        let tint = failed ? ShedColors.error : (snapshot.changesCheckedAt != nil ? ShedColors.primary : ShedColors.muted)
        let icon = failed ? "icloud.slash" : (snapshot.changesCheckedAt != nil ? "checkmark.seal.fill" : "info.circle")

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !snapshot.isRefreshing && (failed || snapshot.changesCheckedAt == nil) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 4)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !snapshot.isRefreshing else { return }
            Haptics.tick()
            Task { await repository.refresh() }
        }
    }

    // MARK: - Days

    @ViewBuilder
    private func dayContent(_ day: ScheduleDay, now: Date, compact: Bool, showBreaks: Bool) -> some View {
        if day.lessons.isEmpty {
            emptyState("Занятий нет", compact: compact)
        } else {
            ForEach(Array(day.lessons.enumerated()), id: \.element.id) { index, lesson in
                LessonBandView(
                    lesson: lesson,
                    date: day.date,
                    now: now,
                    compact: compact,
                    onTap: { if lesson.changed { detailsDay = day } }
                )
                if showBreaks,
                   let next = day.lessons[safe: index + 1],
                   next.startMinutes > lesson.endMinutes {
                    BreakView(
                        date: day.date,
                        from: lesson.endMinutes,
                        until: next.startMinutes,
                        now: now
                    )
                }
            }
        }
    }

    private func weekHeader(_ day: ScheduleDay, today: Date) -> some View {
        HStack(spacing: 8) {
            Text("\(weekdayTitle(day.date)), \(DateFormatters.humanDate.string(from: day.date))")
                .font(.subheadline.weight(.black))
                .foregroundStyle(ScheduleCalendar.sameDay(day.date, today) ? ShedColors.primary : ShedColors.text)
            if day.hasChanges {
                Circle()
                    .fill(ShedColors.error)
                    .frame(width: 7, height: 7)
            }
            Spacer()
        }
        .padding(.top, 18)
        .padding(.bottom, 7)
    }

    private func emptyState(_ text: String, compact: Bool = false) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ShedColors.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 14 : 42)
    }

    private func resolveDay(_ snapshot: ScheduleSnapshot, _ date: Date) -> ScheduleDay? {
        if let day = snapshot.day(on: date) {
            return ScheduleDisplayPolicy.hideCancelled(day)
        }
        if ScheduleCalendar.isSunday(date) {
            return ScheduleDay(
                date: date,
                group: snapshot.group,
                lessons: [],
                hasChanges: false,
                lastUpdated: nil,
                academicWeek: LocalBaseSchedule.weekNumber(for: date)
            )
        }
        let weekday = ScheduleCalendar.weekday(date)
        let week = LocalBaseSchedule.weekNumber(for: date)
        if let match = snapshot.days.first(where: {
            ScheduleCalendar.weekday($0.date) == weekday && $0.academicWeek == week
        }) {
            var copy = match
            copy.date = date
            return ScheduleDisplayPolicy.hideCancelled(copy)
        }
        return nil
    }
}

// MARK: - Lesson card

struct LessonBandView: View {
    let lesson: Lesson
    let date: Date
    let now: Date
    let compact: Bool
    let onTap: () -> Void

    var body: some View {
        let start = ScheduleCalendar.date(on: date, minutes: lesson.startMinutes)
        let end = ScheduleCalendar.date(on: date, minutes: lesson.endMinutes)
        let passed = now > end
        let current = !lesson.cancelled && now >= start && now < end
        let total = max(lesson.endMinutes - lesson.startMinutes, 1)
        let elapsed = min(max(ScheduleCalendar.minutesOfDay(now) - lesson.startMinutes, 0), total)
        let progress = Double(elapsed) / Double(total)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("\(lesson.number)")
                    .font(.system(size: compact ? 27 : 31, weight: .black))
                    .foregroundStyle(current ? ShedColors.onPrimary : ShedColors.primary.opacity(0.72))
                    .frame(width: compact ? 40 : 44, height: compact ? 40 : 44)
                    .background(
                        current ? ShedColors.primary : ShedColors.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.timeText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ShedColors.muted)
                    Text(lesson.subject.isEmpty ? "Занятие" : lesson.subject)
                        .font(.system(size: compact ? 16 : 17, weight: .bold))
                        .lineLimit(2)
                        .strikethrough(lesson.cancelled)
                        .foregroundStyle(ShedColors.text)
                    if !lesson.teacher.isEmpty {
                        Text(lesson.teacher)
                            .font(.caption)
                            .foregroundStyle(ShedColors.muted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 8 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    if lesson.changed || lesson.cancelled {
                        Text(lesson.cancelled ? "ОТМЕНЕНО" : "ИЗМЕНЕНО")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(ShedColors.text)
                    }
                    Text(lesson.isDistance ? "ДИС" : (lesson.room.isEmpty ? "—" : lesson.room))
                        .font(.system(size: lesson.room.count > 4 ? 14 : (compact ? 17 : 19), weight: .black))
                        .foregroundStyle(ShedColors.text)
                        .lineLimit(1)
                }
                .frame(width: compact ? 66 : 72, alignment: .trailing)
                .padding(.trailing, 10)
            }
            .frame(minHeight: compact ? 78 : 94)

            if current {
                ProgressView(value: progress)
                    .tint(ShedColors.primary)
                    .frame(height: 3)
            }
        }
        .background(background(current: current, cancelled: lesson.cancelled))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .opacity(passed ? 0.62 : 1)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if lesson.changed { onTap() }
        }
    }

    private func background(current: Bool, cancelled: Bool) -> Color {
        if cancelled { return ShedColors.error.opacity(0.12) }
        if current { return ShedColors.primary.opacity(0.13) }
        switch lesson.number % 3 {
        case 1: return ShedColors.primary.opacity(0.06)
        case 2: return ShedColors.surfaceVariant.opacity(0.75)
        default: return ShedColors.muted.opacity(0.10)
        }
    }
}

// MARK: - Break

struct BreakView: View {
    let date: Date
    let from: Int
    let until: Int
    let now: Date

    var body: some View {
        let start = ScheduleCalendar.date(on: date, minutes: from)
        let end = ScheduleCalendar.date(on: date, minutes: until)
        let current = now >= start && now < end
        let total = max(until - from, 1)
        let nowMinutes = ScheduleCalendar.minutesOfDay(now)
        let remaining = max(until - nowMinutes, 0)
        let elapsed = Double(min(max(nowMinutes - from, 0), total)) / Double(total)
        let label = current
            ? (remaining < 1 ? "<1 мин" : "до конца \(remaining) мин")
            : "\(total) мин"

        HStack(spacing: 0) {
            Rectangle()
                .fill(current ? ShedColors.primary : ShedColors.outline)
                .frame(width: 2, height: current ? 24 : 15)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Перемена")
                        .font(.caption.weight(current ? .bold : .medium))
                        .foregroundStyle(current ? ShedColors.text : ShedColors.muted)
                    Spacer()
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(current ? ShedColors.text : ShedColors.muted)
                }
                if current {
                    ProgressView(value: elapsed)
                        .tint(ShedColors.primary)
                        .frame(height: 2)
                }
            }
            .padding(.trailing, 10)
        }
        .frame(height: current ? 40 : 32)
    }
}

// MARK: - Changes dialog

struct ChangesDialog: View {
    @Environment(\.dismiss) private var dismiss
    let day: ScheduleDay

    var body: some View {
        let changed = day.lessons.filter { $0.changed }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Изменения")
                            .font(.title2.weight(.black))
                            .foregroundStyle(ShedColors.text)
                        Text(DateFormatters.fullDate.string(from: day.date))
                            .font(.subheadline)
                            .foregroundStyle(ShedColors.muted)
                    }
                    Spacer()
                    Button {
                        Haptics.tick()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ShedColors.text)
                            .frame(width: 40, height: 40)
                            .background(ShedColors.surfaceVariant, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                ForEach(changed) { lesson in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(lesson.number)-я пара · \(lesson.subject)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(ShedColors.text)
                        ForEach(changeDetails(lesson), id: \.self) { detail in
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(ShedColors.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(ShedColors.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if changed.isEmpty {
                    Text("Изменён режим звонков. Новое время уже применено.")
                        .font(.subheadline)
                        .foregroundStyle(ShedColors.muted)
                }

                Button {
                    Haptics.tick()
                    dismiss()
                } label: {
                    Text("Понятно")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(ShedColors.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(ShedColors.onPrimary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(ShedColors.background.ignoresSafeArea())
    }

    private func changeDetails(_ lesson: Lesson) -> [String] {
        var result: [String] = []
        if lesson.cancelled {
            result.append("Пара отменена")
        } else if lesson.changeKinds.contains(.added) {
            result.append("Пара добавлена")
        }
        if lesson.changeKinds.contains(.subject) {
            result.append(valueChange("Предмет", lesson.originalSubject, lesson.subject))
        }
        if lesson.changeKinds.contains(.teacher) {
            result.append(valueChange("Преподаватель", lesson.originalTeacher, lesson.teacher))
        }
        if lesson.changeKinds.contains(.room) {
            result.append(valueChange("Кабинет", roomLabel(lesson.originalRoom), roomLabel(lesson.room)))
        }
        if lesson.changeKinds.contains(.time) {
            if let original = lesson.originalNumber, original != lesson.number {
                result.append("Перенос: \(original)-я → \(lesson.number)-я пара")
            } else {
                result.append("Время: \(lesson.timeText)")
            }
        }
        return result.isEmpty ? ["Актуальные данные применены"] : result
    }

    private func valueChange(_ label: String, _ old: String, _ new: String) -> String {
        if !old.isEmpty && !new.isEmpty && old != new { return "\(label): \(old) → \(new)" }
        if !new.isEmpty { return "\(label): \(new)" }
        return "\(label) изменён"
    }

    private func roomLabel(_ room: String) -> String {
        isDistanceRoom(room) ? "Дистанционно" : room
    }
}

// MARK: - Helpers

func weekdayTitle(_ date: Date) -> String {
    let text = DateFormatters.weekdayFull.string(from: date)
    guard let first = text.first else { return text }
    return String(first).uppercased() + String(text.dropFirst())
}

func relativeDayTitle(_ date: Date, today: Date) -> String {
    switch ScheduleCalendar.dayDistance(from: today, to: date) {
    case 0: return "Сегодня"
    case 1: return "Завтра"
    case 2: return "Послезавтра"
    default: return DateFormatters.weekdayShort.string(from: date)
    }
}

private func weekEyebrow(dates: [Date], today: Date) -> String? {
    guard let first = dates.first else { return nil }
    let currentWeek = ScheduleCalendar.weekStart(today)
    let shownWeek = ScheduleCalendar.weekStart(first)
    let nextWeek = ScheduleCalendar.calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeek)
    switch (shownWeek == currentWeek, shownWeek == nextWeek) {
    case (true, _): return "Эта неделя"
    case (_, true): return "Следующая неделя"
    default: return "Через неделю"
    }
}

private func tabTitle(_ mode: ScheduleMode, actualDay: Date, today: Date) -> String {
    switch mode {
    case .today:
        return relativeDayTitle(actualDay, today: today)
    case .tomorrow:
        return relativeDayTitle(ScheduleDatePolicy.tomorrowTarget(actualDay), today: today)
    case .week:
        return "Неделя"
    case .nextWeek:
        return "Следующая"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
