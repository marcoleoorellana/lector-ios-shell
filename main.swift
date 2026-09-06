import UIKit
import WebKit

// Shell nativo del Lector: un WKWebView a pantalla completa que carga lite-reader/ desde el bundle.
final class ReaderViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        // Permite fetch() entre archivos del bundle (file://). Claves privadas pero estables en iOS 12.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = view.backgroundColor
        webView.isOpaque = false
        view.addSubview(webView)
        loadIndex()
    }

    private func loadIndex() {
        guard let web = Bundle.main.resourceURL?.appendingPathComponent("web", isDirectory: true) else { return }
        webView.loadFileURL(web.appendingPathComponent("index.html"), allowingReadAccessTo: web)
    }

    // Links externos (GitHub, Google Docs) van a Safari; todo lo file:// queda adentro.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // window.open(url, "_blank") -> Safari.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    // Si el proceso web muere (jetsam en 1 GB de RAM), recargar en vez de quedar en blanco.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loadIndex() }

    override var prefersStatusBarHidden: Bool { return true }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        application.isIdleTimerDisabled = true // no apagar la pantalla mientras se lee o predica
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = ReaderViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
