import Foundation

struct DnevnikScheduleError: LocalizedError {
    let code: String
    let message: String

    var errorDescription: String? { message }

    static func authRequired() -> DnevnikScheduleError {
        DnevnikScheduleError(
            code: "auth_required",
            message: "Нужно войти в Дневник.ру: сессия не сохранена или истекла"
        )
    }
}

final class DnevnikScheduleClient {
    private let store: DnevnikSessionStore
    private let session: URLSession

    init(store: DnevnikSessionStore) {
        self.store = store
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: configuration)
    }

    func load(_ urlString: String) async throws -> String {
        guard let stored = store.read() else { throw DnevnikScheduleError.authRequired() }
        guard let target = URL(string: urlString), isAllowed(target) else {
            throw DnevnikScheduleError(code: "url", message: "Некорректный адрес Дневник.ру")
        }

        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(stored.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("ru-RU,ru;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) Shed/1.0", forHTTPHeaderField: "User-Agent")

        let redirectGuard = DnevnikRedirectGuard()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: redirectGuard)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DnevnikScheduleError(code: "network", message: "Не удалось загрузить расписание Дневник.ру")
        }

        guard let http = response as? HTTPURLResponse else {
            throw DnevnikScheduleError(code: "network", message: "Не удалось загрузить расписание Дневник.ру")
        }
        if redirectGuard.blocked {
            throw DnevnikScheduleError(code: "redirect", message: "Дневник.ру перенаправил запрос. Попробуйте войти заново.")
        }
        if let finalURL = http.url, finalURL.host?.lowercased() != "schools.dnevnik.ru" {
            throw DnevnikScheduleError.authRequired()
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw DnevnikScheduleError.authRequired()
        case 403:
            throw DnevnikScheduleError(code: "access_denied", message: "Аккаунту недоступно расписание этой группы")
        case 429:
            throw DnevnikScheduleError(code: "rate_limited", message: "Дневник.ру ограничил частоту запросов. Попробуйте позже")
        case 300...399:
            throw DnevnikScheduleError(code: "redirect", message: "Дневник.ру перенаправил запрос. Попробуйте войти заново.")
        default:
            throw DnevnikScheduleError(code: "http", message: "Дневник.ру вернул ошибку \(http.statusCode)")
        }

        guard data.count <= 8 * 1024 * 1024 else {
            throw DnevnikScheduleError(code: "response_size", message: "Страница расписания слишком большая")
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if !contentType.isEmpty && !contentType.contains("text/html") {
            throw DnevnikScheduleError(code: "response", message: "Дневник.ру вернул неожиданный ответ")
        }

        let encoding = Self.encoding(for: contentType)
        guard let html = String(data: data, encoding: encoding) ?? String(data: data, encoding: .utf8) else {
            throw DnevnikScheduleError(code: "response", message: "Дневник.ру вернул неожиданный ответ")
        }
        if passwordForm.matches(html) {
            throw DnevnikScheduleError.authRequired()
        }
        return html
    }

    private func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https",
              url.user == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return ["schools.dnevnik.ru", "login.dnevnik.ru", "dnevnik.ru"].contains(host)
    }

    private static func encoding(for contentType: String) -> String.Encoding {
        guard let groups = charsetRegex.first(in: contentType), groups.count > 1 else { return .utf8 }
        switch groups[1].lowercased() {
        case "windows-1251", "cp1251": return .windowsCP1251
        case "koi8-r": return .koi8R
        case "iso-8859-5": return .isoLatinCyrillic
        default: return .utf8
        }
    }

    private static let charsetRegex = TextRegex("charset=\"?([A-Za-z0-9_\\-]+)", options: .caseInsensitive)
    private let passwordForm = TextRegex("<input\\b[^>]*type\\s*=\\s*[\"']password[\"']", options: .caseInsensitive)
}

private final class DnevnikRedirectGuard: NSObject, URLSessionTaskDelegate {
    var blocked = false
    private var count = 0

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        count += 1
        guard count <= 5,
              let url = request.url,
              DnevnikPolicy.allowedNavigation(url) else {
            blocked = true
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
