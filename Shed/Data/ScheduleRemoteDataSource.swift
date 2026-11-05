import Foundation

@MainActor
final class ScheduleRemoteDataSource {
    static let userAgent = "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/126.0.0.0 YaBrowser/24.7.0.0 Mobile Safari/537.36"

    private let renderer = ChangesWebRenderer()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = [
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Charset": "utf-8",
            "Accept-Language": "ru-RU,ru;q=0.9,en;q=0.8",
            "User-Agent": ScheduleRemoteDataSource.userAgent
        ]
        session = URLSession(configuration: configuration)
    }

    func loadChangesIndex(group: String) async throws -> String {
        var components = URLComponents(string: "https://www.oat.ru/timetable/Changes/b1")
        components?.queryItems = [URLQueryItem(name: "search", value: group)]
        guard let url = components?.url else {
            throw ScheduleError.network("Некорректный адрес сайта изменений")
        }
        let html = try await fetch(url)
        if isCaptcha(html) {
            throw ScheduleError.source(
                "Сайт запросил проверку (капча). Открой сайт в Safari один раз и повтори обновление."
            )
        }
        if html.contains("/timetable/Changes/")
            || html.localizedCaseInsensitiveContains("Не удалось получить изменения") {
            return html
        }
        // URLSession may receive only the Blazor shell; render it once in WebKit.
        do {
            return try await renderer.renderIndex(url)
        } catch {
            throw ScheduleError.source("Сайт не отдал страницу изменений. \(error.localizedDescription)")
        }
    }

    private func isCaptcha(_ html: String) -> Bool {
        html.localizedCaseInsensitiveContains("Вы не робот")
            || html.localizedCaseInsensitiveContains("smartcaptcha")
            || html.localizedCaseInsensitiveContains("checkcaptcha")
    }

    func loadChangesPages(
        dates: [Date],
        onPage: (Int, Date, String) throws -> Void
    ) async throws {
        for (position, date) in dates.enumerated() {
            try Task.checkCancellation()
            let html = try await renderer.render(changesAddress(date))
            try onPage(position, date, html)
            if position < dates.count - 1 {
                // Preserve the college-friendly request rate.
                try await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    func loadChangesPage(date: Date) async throws -> String {
        try await renderer.render(changesAddress(date))
    }

    private func changesAddress(_ date: Date) -> URL {
        let formatted = DateFormatters.siteDate.string(from: date)
        return URL(string: "https://www.oat.ru/timetable/Changes/b1/\(formatted)")!
    }

    private func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        request.setValue(ScheduleRemoteDataSource.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("ru-RU,ru;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw ScheduleError.network("Сайт расписания вернул ошибку \(code)")
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw ScheduleError.network("Сайт расписания вернул неожиданный ответ")
            }
            return html
        } catch let error as ScheduleError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ScheduleError.network("Не удалось обновить расписание")
        }
    }
}
