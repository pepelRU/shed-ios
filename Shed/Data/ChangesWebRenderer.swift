import Foundation
import WebKit

@MainActor
final class ChangesWebRenderer {
    func render(_ url: URL) async throws -> String {
        try await render(
            url: url,
            script: Self.readPageScript(for: url),
            timeout: 25
        )
    }

    /// The index can also be a Blazor shell. It is accepted after a short grace
    /// period even without dated links, because "no changes published" is valid.
    func renderIndex(_ url: URL) async throws -> String {
        try await render(
            url: url,
            script: Self.readIndexScript(for: url),
            timeout: 10
        )
    }

    private func render(url: URL, script: String, timeout: TimeInterval) async throws -> String {
        guard url.scheme == "https", url.host?.lowercased() == "www.oat.ru" else {
            throw ScheduleError.network("Некорректный адрес сайта изменений")
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        webView.customUserAgent = ScheduleRemoteDataSource.userAgent
        webView.load(URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        ))

        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 150_000_000)

            let raw: Any?
            do {
                raw = try await webView.evaluateJavaScript(script)
            } catch {
                continue
            }
            guard let result = raw as? String,
                  let data = result.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any] else { continue }

            if dictionary["ready"] as? Bool == true,
               let html = dictionary["html"] as? String,
               !html.isEmpty {
                return html
            }
        }

        throw ScheduleError.network("Сайт не успел подготовить изменения расписания")
    }

    private static func readPageScript(for url: URL) -> String {
        let escaped = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (() => {
          if (location.origin + location.pathname !== new URL("\(escaped)").origin + new URL("\(escaped)").pathname)
            return JSON.stringify({ ready: false, html: '' });
          const root = document.documentElement;
          const main = document.querySelector('main');
          if (!root || !main) return JSON.stringify({ ready: false, html: '' });
          const tables = Array.from(main.querySelectorAll('table'));
          const changes = tables.find(table => {
            const headings = Array.from(table.querySelectorAll('th'))
              .map(cell => (cell.innerText || '').trim().toLowerCase());
            return headings.includes('группа') && headings.some(value => value.includes('дисциплин'));
          });
          const text = (main.innerText || '').toLowerCase();
          const failed = text.includes('не удалось получить изменения');
          const noChanges = text.includes('изменений нет') || text.includes('нет изменений') || text.includes('не опубликован');
          const key = '__shedPageStarted';
          if (!window[key]) window[key] = Date.now();
          const fallback = Date.now() - window[key] > 10000 && text.trim().length > 0;
          const ready = Boolean(changes) || failed || noChanges || fallback;
          return JSON.stringify({ ready: ready, html: ready ? root.outerHTML : '' });
        })()
        """
    }

    private static func readIndexScript(for url: URL) -> String {
        let escaped = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (() => {
          if (location.origin + location.pathname !== new URL("\(escaped)").origin + new URL("\(escaped)").pathname)
            return JSON.stringify({ ready: false, html: '' });
          const root = document.documentElement;
          const main = document.querySelector('main');
          if (!root || !main) return JSON.stringify({ ready: false, html: '' });
          const text = (main.innerText || '').trim();
          const links = main.querySelectorAll('a[href*="/timetable/Changes/"]').length;
          const failed = text.toLowerCase().includes('не удалось получить изменения');
          if (links > 0 || failed)
            return JSON.stringify({ ready: true, html: root.outerHTML });
          const key = '__shedIndexStarted';
          if (!window[key]) window[key] = Date.now();
          const stable = Date.now() - window[key] > 4000 && text.length > 0;
          return JSON.stringify({ ready: stable, html: stable ? root.outerHTML : '' });
        })()
        """
    }
}
