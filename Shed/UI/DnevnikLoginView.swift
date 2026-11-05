import SwiftUI
import WebKit

@MainActor
final class DnevnikLoginModel: ObservableObject {
    @Published var message = "Омская область. Нажми «Войти через Госуслуги» и заверши вход. Пароль Shed не читает и не сохраняет."
    @Published var completed = false

    private var extracting = false

    func pageFinished(auth: DnevnikAuth) {
        guard !completed, !extracting else { return }
        extracting = true
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self else { return }
                self.extracting = false
                guard !self.completed else { return }
                let a = cookies.first(where: { $0.name == DnevnikPolicy.authA })?.value
                let l = cookies.first(where: { $0.name == DnevnikPolicy.authL })?.value
                guard let session = DnevnikSession(a: a, l: l) else { return }
                self.completed = true
                auth.save(session)
                self.message = "Готово. Расписание из Дневник.ру подключено."
                WKWebsiteDataStore.default().removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                    modifiedSince: .distantPast
                ) {}
            }
        }
    }

    func blocked(_ text: String) {
        message = text
    }
}

struct DnevnikLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: DnevnikAuth

    let onComplete: (Bool) -> Void
    @StateObject private var model = DnevnikLoginModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Закрыть") {
                    onComplete(false)
                    dismiss()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ShedColors.muted)
                Spacer()
                Text("Дневник.ру")
                    .font(.headline)
                    .foregroundStyle(ShedColors.text)
                Spacer()
                Text("Закрыть")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.clear)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Text(model.message)
                .font(.caption)
                .foregroundStyle(ShedColors.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            DnevnikWebView(
                onPageFinished: { model.pageFinished(auth: auth) },
                onBlocked: { model.blocked($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(ShedColors.background.ignoresSafeArea())
        .onChange(of: model.completed) { _, completed in
            guard completed else { return }
            Haptics.confirm()
            onComplete(true)
            dismiss()
        }
        .onDisappear {
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {}
        }
    }
}

struct DnevnikWebView: UIViewRepresentable {
    let onPageFinished: () -> Void
    let onBlocked: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: DnevnikPolicy.loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPageFinished = onPageFinished
        context.coordinator.onBlocked = onBlocked
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageFinished: onPageFinished, onBlocked: onBlocked)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onPageFinished: () -> Void
        var onBlocked: (String) -> Void

        init(onPageFinished: @escaping () -> Void, onBlocked: @escaping (String) -> Void) {
            self.onPageFinished = onPageFinished
            self.onBlocked = onBlocked
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if let upgraded = DnevnikPolicy.upgradedSchoolURL(url) {
                webView.load(URLRequest(url: upgraded))
                decisionHandler(.cancel)
                return
            }
            guard DnevnikPolicy.allowedNavigation(url) else {
                onBlocked("Этот адрес не входит в разрешённую цепочку входа. Вернись назад к официальной странице Дневник.ру.")
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onPageFinished()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onBlocked("Страница входа не загрузилась. Проверь интернет и попробуй вернуться назад.")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onBlocked("Страница входа не загрузилась. Проверь интернет и попробуй вернуться назад.")
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
