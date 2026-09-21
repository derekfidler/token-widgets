import SwiftUI
import WebKit

enum LoginProduct: String, Identifiable {
    case claude
    case chatgpt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        }
    }

    var loginURL: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/login")!
        case .chatgpt: return URL(string: "https://chatgpt.com/auth/login")!
        }
    }

    /// Domains to pull cookies from. We grab everything under these rather than guessing
    /// one specific cookie name, since that name is undocumented and can change without notice.
    var cookieDomains: [String] {
        switch self {
        case .claude: return ["claude.ai"]
        case .chatgpt: return ["chatgpt.com", "openai.com"]
        }
    }
}

/// Hosts the WKWebView and exposes an on-demand cookie dump, instead of trying to guess the
/// exact moment login finished. Single-page apps like chatgpt.com only fire one full-page
/// "did finish navigating" event; everything after that (including the auth handshake
/// completing) happens client-side with no further signal to hook into. So capture is
/// user-triggered: you click "Continue" once you can see you're actually logged in.
final class LoginWebViewController: NSObject, ObservableObject {
    let webView: WKWebView

    override init() {
        webView = WKWebView()
        super.init()
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func captureCookieHeader(forDomains domains: [String], completion: @escaping (String?) -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let matching = cookies.filter { cookie in
                let cookieDomain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return domains.contains { allowedDomain in
                    cookieDomain == allowedDomain || cookieDomain.hasSuffix(".\(allowedDomain)")
                }
            }
            guard !matching.isEmpty else {
                completion(nil)
                return
            }
            let header = matching
                .sorted { ($0.domain, $0.path, $0.name) < ($1.domain, $1.path, $1.name) }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            completion(header)
        }
    }
}

struct LoginWebView: NSViewRepresentable {
    let controller: LoginWebViewController

    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct LoginCaptureSheet: View {
    let product: LoginProduct
    /// Passes the full "name=value; name2=value2" Cookie header, not a single cookie's value.
    let onCaptured: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = LoginWebViewController()
    @State private var isCapturing = false
    @State private var captureFailed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log in to \(product.displayName)")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            LoginWebView(controller: controller)
                .onAppear { controller.load(product.loginURL) }

            Divider()

            HStack {
                if captureFailed {
                    Text("No session cookies found yet — make sure the page above shows you fully logged in, then try again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    capture()
                } label: {
                    if isCapturing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("I'm logged in — Continue")
                    }
                }
                .disabled(isCapturing)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 680)
    }

    private func capture() {
        isCapturing = true
        captureFailed = false
        controller.captureCookieHeader(forDomains: product.cookieDomains) { header in
            isCapturing = false
            if let header {
                onCaptured(header)
                dismiss()
            } else {
                captureFailed = true
            }
        }
    }
}
