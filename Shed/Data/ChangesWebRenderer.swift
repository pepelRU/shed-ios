import Foundation
import WebKit

@MainActor
final class ChangesWebRenderer {
    func render(_ url: URL) async throws -> String {
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

        let script = Self.readPageScript(for: url)
        let deadline = Date().addingTimeInterval(15)
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
          const failed = (main.innerText || '').toLowerCase().includes('не удалось получить изменения');
          const ready = Boolean(changes) || failed;
          return JSON.stringify({ ready: ready, html: ready ? root.outerHTML : '' });
        })()
        """
    }
}
