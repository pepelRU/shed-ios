import Foundation
import Combine

@MainActor
final class ScheduleRepository: ObservableObject {
    @Published private(set) var snapshot: ScheduleSnapshot
    @Published private(set) var refreshStage: ScheduleRefreshStage = .idle
    @Published private(set) var refreshProgress = ScheduleRefreshProgress()
    @Published private(set) var lastChangeSummary = ScheduleChangeSummary.empty

    private let preferences: SchedulePreferences
    private let cache: ScheduleCache
    private let remote: ScheduleRemoteDataSource
    private let parser: ScheduleHtmlParser
    private let dnevnik: DnevnikScheduleSource?
    private let dnevnikAuth: DnevnikAuth?

    init(
        preferences: SchedulePreferences,
        cache: ScheduleCache,
        remote: ScheduleRemoteDataSource,
        parser: ScheduleHtmlParser,
        dnevnik: DnevnikScheduleSource?,
        dnevnikAuth: DnevnikAuth?
    ) {
        self.preferences = preferences
        self.cache = cache
        self.remote = remote
        self.parser = parser
        self.dnevnik = dnevnik
        self.dnevnikAuth = dnevnikAuth

        let group = preferences.currentGroup()
        snapshot = cache.read(group: group) ?? Self.localSnapshot(group: group)
    }

    static func localSnapshot(group: String) -> ScheduleSnapshot {
        let today = ScheduleCalendar.today()
        let days = ScheduleDatePolicy.loadingWindow(today: today).map {
            LocalBaseSchedule.day(for: $0, group: group)
        }
        return ScheduleSnapshot(group: group, days: days)
    }

    func refreshBaseIfNeeded() async {
        if snapshot.changesCheckedAt == nil {
            _ = await refresh()
        }
    }

    /// Refreshes on launch and after returning to the app, but not more often
    /// than the given interval.
    func refreshIfStale(interval: TimeInterval = 2 * 60) async {
        if let checked = snapshot.changesCheckedAt,
           Date().timeIntervalSince(checked) < interval {
            return
        }
        _ = await refresh()
    }

    @discardableResult
    func refresh() async -> ScheduleRefreshResult {
        guard !snapshot.isRefreshing else {
            return ScheduleRefreshResult(successful: false)
        }

        let group = preferences.currentGroup()
        var existing = snapshot.group.caseInsensitiveCompare(group) == .orderedSame
            ? snapshot
            : (cache.read(group: group) ?? Self.localSnapshot(group: group))
        existing.isRefreshing = true
        existing.errorMessage = nil
        snapshot = existing
        refreshProgress = ScheduleRefreshProgress()

        do {
            let fresh = try await loadFresh(group: group, existing: existing)
            let oldVisible = ScheduleSubgroupFilter.apply(existing.days, subgroup: preferences.subgroup)
            let newVisible = ScheduleSubgroupFilter.apply(fresh.days, subgroup: preferences.subgroup)
            let changes = existing.changesCheckedAt == nil
                ? ScheduleChangeSummary.empty
                : ScheduleChangeDetector.detect(
                    oldDays: oldVisible,
                    newDays: newVisible,
                    today: ScheduleCalendar.today()
                )

            refreshStage = .saving
            cache.write(fresh)
            snapshot = fresh
            lastChangeSummary = changes
            refreshStage = .success
            return ScheduleRefreshResult(successful: true, changeSummary: changes)
        } catch is CancellationError {
            var preserved = existing
            preserved.isRefreshing = false
            snapshot = preserved
            refreshStage = .idle
            return ScheduleRefreshResult(successful: false)
        } catch {
            var preserved = existing
            preserved.isRefreshing = false
            preserved.errorMessage = friendlyError(error)
            preserved.fromCache = existing.changesCheckedAt != nil
            preserved.changesCheckFailed = true
            cache.write(preserved)
            snapshot = preserved
            refreshStage = .error
            return ScheduleRefreshResult(successful: false)
        }
    }

    private func loadFresh(group: String, existing: ScheduleSnapshot) async throws -> ScheduleSnapshot {
        let today = ScheduleCalendar.today()
        let dates = ScheduleDatePolicy.changesWindow(today: today, period: preferences.refreshPeriod)

        if let dnevnik, dnevnik.hasSession {
            do {
                return try await loadDnevnik(dnevnik, group: group, dates: dates)
            } catch let error as DnevnikScheduleError {
                if error.code == "auth_required" {
                    dnevnik.forgetSession()
                    dnevnikAuth?.sessionInvalidated()
                }
                // Dnevnik is a bonus source: fall back to the base + published
                // changes instead of leaving the user without an update.
            }
        }

        refreshStage = .checkingPublishedDates
        let indexHTML = try await remote.loadChangesIndex(group: group)
        let index = try parser.parseChanges(html: indexHTML, date: today, group: group)
        guard index.available else {
            throw ScheduleError.source("Сайт не подтвердил актуальность изменений")
        }

        let publishedDates = index.availableDates
            .intersection(Set(dates))
            .sorted()

        refreshStage = .loadingChanges
        var changesByDate: [Date: ScheduleChangeSet] = [:]
        var failures: [String] = []
        refreshProgress = ScheduleRefreshProgress(
            current: publishedDates.isEmpty ? 0 : 1,
            total: publishedDates.count
        )

        for (position, date) in publishedDates.enumerated() {
            do {
                let html = try await remote.loadChangesPage(date: date)
                let changes = try parser.parseChanges(html: html, date: date, group: group)
                if changes.available {
                    changesByDate[date] = changes
                } else {
                    let formatted = DateFormatters.dayMonth.string(from: date)
                    failures.append("\(formatted): изменения не загрузились")
                }
            } catch {
                let formatted = DateFormatters.dayMonth.string(from: date)
                failures.append("\(formatted): \(error.localizedDescription)")
            }

            refreshProgress = ScheduleRefreshProgress(
                current: min(position + 2, publishedDates.count),
                total: publishedDates.count
            )
            if position < publishedDates.count - 1 {
                // Keep the college site from being hammered by the browser.
                try await Task.sleep(nanoseconds: 800_000_000)
            }
        }

        if changesByDate.isEmpty, !publishedDates.isEmpty, let firstFailure = failures.first {
            throw ScheduleError.source("Не удалось загрузить изменения. \(firstFailure)")
        }

        refreshStage = .applyingChanges
        let checkedAt = Date()
        let days = ScheduleRefreshPolicy.refreshedScheduleDays(
            today: today,
            group: group,
            previousDays: existing.days,
            changesByDate: changesByDate,
            checkedAt: checkedAt,
            checkedDates: Set(dates)
        )
        return ScheduleSnapshot(
            group: group,
            days: days,
            lastUpdated: checkedAt,
            isRefreshing: false,
            errorMessage: nil,
            fromCache: false,
            subgroup: preferences.subgroup,
            changesCheckedAt: checkedAt,
            changesCheckFailed: false
        )
    }

    private func loadDnevnik(
        _ source: DnevnikScheduleSource,
        group: String,
        dates: [Date]
    ) async throws -> ScheduleSnapshot {
        refreshStage = .loadingChanges
        refreshProgress = ScheduleRefreshProgress(current: 0, total: dates.count)
        let days = try await source.load(dates: dates) { [weak self] done, total in
            self?.refreshProgress = ScheduleRefreshProgress(current: done, total: total)
        }

        refreshStage = .applyingChanges
        let checkedAt = Date()
        return ScheduleSnapshot(
            group: group,
            days: days,
            lastUpdated: checkedAt,
            isRefreshing: false,
            errorMessage: nil,
            fromCache: false,
            subgroup: preferences.subgroup,
            changesCheckedAt: checkedAt,
            changesCheckFailed: false
        )
    }

    private func friendlyError(_ error: Error) -> String {
        if let error = error as? ScheduleError {
            return error.errorDescription ?? "Не удалось обновить расписание"
        }
        if let error = error as? DnevnikScheduleError {
            return error.message
        }
        return "Не удалось обновить расписание. Попробуйте переключиться между Wi-Fi и мобильным интернетом. "
            + "Если вы используете мобильную сеть, включите режим полёта на 10 секунд и повторите."
    }
}
