import SwiftUI
import WebKit

struct WebViewWindow: View {
    @Environment(AppModel.self) private var appModel
    var sourceID: String

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var reloadToken = UUID()
    @State private var pinned = false
    @State private var scale = 1.0

    private var source: ContentSourceItem? {
        appModel.sourceDetails[sourceID] ?? appModel.sources.first(where: { $0.id == sourceID }) ?? appModel.selectedSource
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            ZStack {
                WebViewRepresentable(
                    url: source.flatMap { appModel.sourceURLWithAuth($0) },
                    reloadToken: reloadToken,
                    isLoading: $isLoading,
                    loadError: $loadError
                )
                if isLoading {
                    ProgressView("正在加载网页...")
                }
                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .scaleEffect(scale)
        }
        .background(Color.black.opacity(0.92))
        .onAppear {
            let pref = appModel.windowPreference(sourceID: sourceID)
            pinned = pref.pinned
            scale = pref.scale
        }
        .onChange(of: pinned) { _, value in
            appModel.setWindowPreference(sourceID: sourceID, pinned: value, scale: scale)
        }
        .onChange(of: scale) { _, value in
            appModel.setWindowPreference(sourceID: sourceID, pinned: pinned, scale: value)
        }
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            Text(source?.name ?? "网页窗口")
                .font(.headline)
            Spacer()
            Button("刷新") {
                loadError = nil
                isLoading = true
                reloadToken = UUID()
            }
            .buttonStyle(.bordered)
            Toggle(isOn: $pinned) {
                Image(systemName: pinned ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            Slider(value: $scale, in: 0.7...1.4)
                .frame(width: 100)
        }
        .padding(12)
        .background(.thinMaterial)
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL?
    let reloadToken: UUID
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url else { return }
        if context.coordinator.currentURL != url.absoluteString || context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.currentURL = url.absoluteString
            context.coordinator.lastReloadToken = reloadToken
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewRepresentable
        var currentURL: String?
        var lastReloadToken: UUID?

        init(parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                parent.isLoading = true
                parent.loadError = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                parent.isLoading = false
                parent.loadError = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                parent.isLoading = false
                parent.loadError = error.localizedDescription
            }
        }
    }
}
