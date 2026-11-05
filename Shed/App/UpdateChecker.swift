import Foundation
import Combine

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var state: UpdateCheckState = .idle

    func check(force: Bool = false) async {
        if case .checking = state { return }
        guard let manifest = Bundle.main.object(forInfoDictionaryKey: "UpdateManifestURL") as? String,
              manifest.hasPrefix("https://"),
              let url = URL(string: manifest) else {
            state = .idle
            return
        }

        state = .checking
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Shed/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
            let currentText = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
            let current = Int(currentText) ?? 1
            state = info.build > current ? .available(info) : .upToDate
        } catch {
            state = force ? .error("Не удалось проверить обновления") : .idle
        }
    }
}
