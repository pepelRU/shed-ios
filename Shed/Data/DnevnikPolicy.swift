import Foundation

enum DnevnikPolicy {
    static let authA = "DnevnikAuth_a"
    static let authL = "DnevnikAuth_l"
    static let loginURL = URL(string: "https://55.dnevnik.ru/")!
    static let schedulePage = "https://schools.dnevnik.ru/v2/r/omsk/schedules/view?school=53237&group=2527502621979585430"

    private static let dnevnikHosts: Set<String> = [
        "dnevnik.ru",
        "55.dnevnik.ru",
        "schools.dnevnik.ru",
        "login.dnevnik.ru",
        "aisgu-esia.dnevnik.ru"
    ]

    static func allowedNavigation(_ url: URL) -> Bool {
        guard url.scheme == "https",
              url.user == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return dnevnikHosts.contains(host)
            || host == "gosuslugi.ru"
            || host.hasSuffix(".gosuslugi.ru")
            || host == "omskportal.ru"
            || host.hasSuffix(".omskportal.ru")
    }

    static func upgradedSchoolURL(_ url: URL) -> URL? {
        guard url.scheme == "http",
              url.host?.lowercased() == "schools.dnevnik.ru",
              url.user == nil,
              url.port == nil else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url
    }

    static func scheduleReached(_ url: URL) -> Bool {
        guard allowedNavigation(url), url.host?.lowercased() == "schools.dnevnik.ru" else { return false }
        return url.path == "/v2/schedules/view" || url.path == "/v2/r/omsk/schedules/view"
    }

    /// After the ESIA redirect the browser may land on a Dnevnik landing page
    /// without the school cookie. The schedule page forces it to be issued.
    static func canOpenSchedule(_ url: URL) -> Bool {
        guard allowedNavigation(url), let host = url.host?.lowercased() else { return false }
        return host.hasSuffix("dnevnik.ru") && !scheduleReached(url)
    }
}
