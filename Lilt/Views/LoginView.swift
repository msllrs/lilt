import SwiftUI
import WebKit

/// Google sign-in, shown in its own centered window (the column is too narrow for a sheet).
struct LoginView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        LoginWebView(dataStore: auth.dataStore) {
            await auth.refresh()
            if auth.isSignedIn { auth.isPresentingLogin = false }
        }
        .frame(width: 480, height: 680)
    }
}

/// A web view pointed at Google sign-in. Each completed navigation re-checks the cookie jar.
private struct LoginWebView: NSViewRepresentable {
    let dataStore: WKWebsiteDataStore
    let onNavigated: @MainActor () async -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onNavigated: onNavigated) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        // Google's passkey prompt doesn't work inside WKWebView; hide the capability so it
        // falls back to a password flow.
        config.userContentController.addUserScript(
            WKUserScript(
                source: "Object.defineProperty(window, 'PublicKeyCredential', { value: undefined });",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = InnerTubeClient.safariUserAgent
        webView.navigationDelegate = context.coordinator
        let url = URL(string: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com%2F&hl=en")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let onNavigated: @MainActor () async -> Void

        init(onNavigated: @escaping @MainActor () async -> Void) { self.onNavigated = onNavigated }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { await onNavigated() }
        }
    }
}
