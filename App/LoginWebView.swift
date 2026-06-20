import SwiftUI
import WebKit

/// A WKWebView (AppKit) that loads Anthropic's OAuth authorize page and
/// intercepts the redirect to the callback URL to capture the authorization code.
struct LoginWebView: NSViewRepresentable {
    let url: URL
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: LoginWebView
        init(_ parent: LoginWebView) { self.parent = parent }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  url.absoluteString.hasPrefix(Config.redirectURI),
                  let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                decisionHandler(.allow)
                return
            }

            let items = comps.queryItems ?? []
            if let code = items.first(where: { $0.name == "code" })?.value {
                let state = items.first(where: { $0.name == "state" })?.value
                let raw = state.map { "\(code)#\($0)" } ?? code
                decisionHandler(.cancel)
                parent.onCode(raw)
            } else if let err = items.first(where: { $0.name == "error" })?.value {
                decisionHandler(.cancel)
                parent.onError(err)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!, withError error: Error) {
            parent.onError(error.localizedDescription)
        }
    }
}
