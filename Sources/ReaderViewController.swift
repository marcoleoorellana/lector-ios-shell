import UIKit
import WebKit

/// Lector: WKWebView con el HTML del doc envuelto en nuestro CSS (Figtree + jerarquía de Docs desde styles.json).
final class ReaderViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler, UIPopoverPresentationControllerDelegate {
    private let doc: Doc
    private var webView: WKWebView!
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let statusLabel = UILabel()      // "14:32 · 62%" en la barra
    private let preachLabel = UILabel()      // esquina, en modo predicación
    private var progress: Double = 0
    private var timer: Timer?
    private let started = Date()
    private var preaching = false
    var debugPreach = false
    private var pal: Palette { return Settings.shared.palette }

    init(doc: Doc) { self.doc = doc; super.init(nibName: nil, bundle: nil); hidesBottomBarWhenPushed = true }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        statusLabel.font = Fonts.mono(13); statusLabel.textAlignment = .center
        navigationItem.titleView = statusLabel
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Predicar", style: .plain, target: self, action: #selector(togglePreach)),
            UIBarButtonItem(title: "Aa", style: .plain, target: self, action: #selector(showTypography))
        ]
        navigationItem.rightBarButtonItems?.forEach { $0.setTitleTextAttributes([.font: Fonts.ui(17, weight: .medium)], for: .normal) }

        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "lector")
        cfg.userContentController.addUserScript(WKUserScript(source: ReaderHTML.bridgeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        cfg.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: view.bounds, configuration: cfg)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        view.addSubview(webView)

        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressTrack)
        NSLayoutConstraint.activate([
            progressTrack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressTrack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressTrack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 2)
        ])
        progressTrack.addSubview(progressFill)

        preachLabel.font = Fonts.mono(13); preachLabel.alpha = 0
        preachLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preachLabel)
        NSLayoutConstraint.activate([
            preachLabel.topAnchor.constraint(equalTo: progressTrack.bottomAnchor, constant: 12),
            preachLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        applyTheme()
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateStatus() }
    }

    deinit { timer?.invalidate(); webView?.configuration.userContentController.removeScriptMessageHandler(forName: "lector") }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { exitPreachIfNeeded() }
    }

    override var prefersStatusBarHidden: Bool { return preaching }
    override var prefersHomeIndicatorAutoHidden: Bool { return preaching }

    private func load() {
        let html = ReaderHTML.wrap(body: ContentStore.shared.html(for: doc), title: doc.title,
                                   styles: ContentStore.shared.styles, settings: Settings.shared, preach: preaching)
        webView.loadHTMLString(html, baseURL: ContentStore.shared.baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if debugPreach && !preaching { debugPreach = false; togglePreach() }
        let p = ContentStore.shared.progress(for: doc.id)
        if p > 0.01 && p < 0.97 { webView.evaluateJavaScript("window.__lectorRestore(\(p))", completionHandler: nil) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
           let s = url.scheme?.lowercased(), s == "http" || s == "https" {
            UIApplication.shared.open(url); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    // Mensajes desde el JS: progreso, tap, doble tap.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "progress":
            progress = (body["p"] as? Double) ?? 0
            ContentStore.shared.setProgress(progress, for: doc.id)
            updateStatus()
        case "tap":
            if preaching {
                let y = (body["y"] as? Double) ?? 0, h = (body["h"] as? Double) ?? 1
                webView.evaluateJavaScript("window.__lectorPage(\(y < h * 0.3 ? -1 : 1))", completionHandler: nil)
            } else {
                let hidden = navigationController?.isNavigationBarHidden ?? false
                navigationController?.setNavigationBarHidden(!hidden, animated: true)
            }
        case "doubletap":
            if preaching { togglePreach() }
        default: break
        }
    }

    private func updateStatus() {
        let s = Int(Date().timeIntervalSince(started))
        let clock = String(format: "%02d:%02d", s / 60, s % 60)
        let pct = "\(Int(progress * 100))%"
        statusLabel.text = "\(clock) · \(pct)"
        statusLabel.sizeToFit()
        preachLabel.text = "PREDICACIÓN · \(clock) · \(pct)"
        let w = progressTrack.bounds.width * CGFloat(progress)
        progressFill.frame = CGRect(x: 0, y: 0, width: w, height: 2)
    }

    @objc private func applyTheme() {
        view.backgroundColor = pal.bg; webView.backgroundColor = pal.bg; webView.scrollView.backgroundColor = pal.bg
        progressTrack.backgroundColor = pal.hairline; progressFill.backgroundColor = pal.text
        statusLabel.textColor = pal.secondary; preachLabel.textColor = pal.secondary
        navigationController?.navigationBar.barTintColor = pal.bg
        navigationController?.navigationBar.tintColor = pal.text
        navigationController?.navigationBar.barStyle = Settings.shared.theme == .dark ? .black : .default
        pushCSSVars()
    }

    /// Cambios en vivo sin recargar: variables CSS.
    private func pushCSSVars() {
        let s = Settings.shared
        let js = ReaderHTML.cssVarsJS(settings: s, preach: preaching)
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc private func togglePreach() {
        preaching.toggle()
        navigationController?.setNavigationBarHidden(preaching, animated: true)
        UIView.animate(withDuration: 0.2) { self.preachLabel.alpha = self.preaching ? 1 : 0 }
        setNeedsStatusBarAppearanceUpdate()
        webView.evaluateJavaScript("document.body.classList.toggle('preach', \(preaching))", completionHandler: nil)
        pushCSSVars()
    }

    private func exitPreachIfNeeded() {
        if preaching { preaching = false; navigationController?.setNavigationBarHidden(false, animated: false) }
    }

    @objc private func showTypography() {
        let vc = TypographyViewController { [weak self] in self?.pushCSSVars() }
        vc.modalPresentationStyle = .popover
        vc.preferredContentSize = CGSize(width: 320, height: 190)
        vc.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
        vc.popoverPresentationController?.delegate = self
        vc.popoverPresentationController?.backgroundColor = pal.bg
        present(vc, animated: true)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { return .none }
}

/// Popover "Aa": tamaño y tema, aplicados en vivo.
final class TypographyViewController: UIViewController {
    private let onChange: () -> Void
    private let sizeLabel = UILabel()
    init(onChange: @escaping () -> Void) { self.onChange = onChange; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let pal = Settings.shared.palette
        view.backgroundColor = pal.bg
        let smaller = UIButton(type: .system), bigger = UIButton(type: .system)
        smaller.setTitle("A", for: .normal); smaller.titleLabel?.font = Fonts.ui(15)
        bigger.setTitle("A", for: .normal); bigger.titleLabel?.font = Fonts.ui(24)
        for b in [smaller, bigger] { b.tintColor = pal.text; b.layer.borderWidth = 1; b.layer.borderColor = pal.hairline.cgColor; b.layer.cornerRadius = 8 }
        smaller.addTarget(self, action: #selector(dec), for: .touchUpInside)
        bigger.addTarget(self, action: #selector(inc), for: .touchUpInside)
        sizeLabel.font = Fonts.mono(13); sizeLabel.textColor = pal.secondary; sizeLabel.textAlignment = .center
        let sizeRow = UIStackView(arrangedSubviews: [smaller, sizeLabel, bigger]); sizeRow.axis = .horizontal; sizeRow.distribution = .fillEqually; sizeRow.spacing = 12
        sizeRow.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let seg = UISegmentedControl(items: ["Claro", "Sepia", "Oscuro"])
        seg.selectedSegmentIndex = [ThemeMode.light, .sepia, .dark].firstIndex(of: Settings.shared.theme) ?? 0
        seg.tintColor = pal.text
        seg.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [sizeRow, seg]); stack.axis = .vertical; stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        refresh()
    }
    private func refresh() { sizeLabel.text = "\(Int(Settings.shared.fontSize)) px" }
    @objc private func dec() { Settings.shared.fontSize -= 1; refresh(); onChange() }
    @objc private func inc() { Settings.shared.fontSize += 1; refresh(); onChange() }
    @objc private func themeChanged(_ s: UISegmentedControl) {
        Settings.shared.theme = [ThemeMode.light, .sepia, .dark][s.selectedSegmentIndex]
        dismiss(animated: true)
    }
}

/// Construcción del HTML del lector.
enum ReaderHTML {
    /// Tamaño en pt de un estilo con nombre de Docs (styles.json), o el default de Docs.
    private static func pt(_ styles: [String: [String: Any]], _ key: String, _ fallback: Double) -> Double {
        if let v = styles[key]?["fontSizePt"] as? Double, v > 0 { return v }
        if let v = styles[key]?["fontSizePt"] as? Int, v > 0 { return Double(v) }
        return fallback
    }
    private static func flag(_ styles: [String: [String: Any]], _ key: String, _ name: String, _ fallback: Bool) -> Bool {
        return (styles[key]?[name] as? Bool) ?? fallback
    }

    static func cssVarsJS(settings s: Settings, preach: Bool) -> String {
        let pal = s.palette
        let base = preach ? s.preachFontSize : s.fontSize
        let alpha = preach ? 0.55 : 0.35
        return """
        (function(){var r=document.documentElement.style;
        r.setProperty('--fs','\(base)px');r.setProperty('--bg','\(pal.bgHex)');r.setProperty('--fg','\(pal.textHex)');
        r.setProperty('--muted','\(pal.secondaryHex)');r.setProperty('--line','\(pal.hairlineHex)');r.setProperty('--tint','\(alpha)');})();
        """
    }

    static func wrap(body: String, title: String, styles: [String: [String: Any]], settings s: Settings, preach: Bool) -> String {
        let pal = s.palette
        let normal = pt(styles, "NORMAL_TEXT", 11)
        // Escala: el texto normal de Docs (en pt) se ve a --fs px; los encabezados mantienen la proporción de Docs.
        func em(_ key: String, _ fb: Double) -> String { return String(format: "%.3fem", pt(styles, key, fb) / normal) }
        func deco(_ key: String, bold: Bool, italic: Bool, underline: Bool) -> String {
            let b = flag(styles, key, "bold", bold), i = flag(styles, key, "italic", italic), u = flag(styles, key, "underline", underline)
            return "font-weight:\(b ? 700 : 400);font-style:\(i ? "italic" : "normal");text-decoration:\(u ? "underline" : "none");"
        }
        let dark = s.theme == .dark
        let css = """
        @font-face{font-family:Figtree;src:url('fonts/Figtree-Regular.ttf');font-weight:400;font-style:normal}
        @font-face{font-family:Figtree;src:url('fonts/Figtree-RegularItalic.ttf');font-weight:400;font-style:italic}
        @font-face{font-family:Figtree;src:url('fonts/Figtree-Medium.ttf');font-weight:500;font-style:normal}
        @font-face{font-family:Figtree;src:url('fonts/Figtree-SemiBold.ttf');font-weight:600;font-style:normal}
        @font-face{font-family:Figtree;src:url('fonts/Figtree-SemiBoldItalic.ttf');font-weight:600;font-style:italic}
        @font-face{font-family:Figtree;src:url('fonts/Figtree-Bold.ttf');font-weight:700;font-style:normal}
        @font-face{font-family:Figtree;src:url('fonts/Figtree-BoldItalic.ttf');font-weight:700;font-style:italic}
        :root{--fs:\(preach ? s.preachFontSize : s.fontSize)px;--bg:\(pal.bgHex);--fg:\(pal.textHex);--muted:\(pal.secondaryHex);--line:\(pal.hairlineHex);--tint:\(preach ? 0.55 : 0.35)}
        html{background:var(--bg);-webkit-text-size-adjust:100%}
        body{margin:0;padding:28px 0 120px;background:var(--bg);color:var(--fg);font-family:Figtree,-apple-system,Helvetica,sans-serif;font-size:var(--fs);line-height:1.45;-webkit-font-smoothing:antialiased;-webkit-tap-highlight-color:transparent}
        article{max-width:640px;margin:0 auto;padding:0 32px}
        body.preach article{max-width:720px}
        p{margin:0 0 .6em}
        p:empty,p.is-section-break{margin:0;height:.6em}
        li{margin:0 0 .15em}
        li>p{margin:0}
        ul,ol{margin:.2em 0 .6em;padding-left:1.25em}
        br+br{display:none}
        a{color:var(--fg)}
        img{max-width:100%;height:auto}
        table{border-collapse:collapse;width:100%;font-size:.9em}
        td,th{border:1px solid var(--line);padding:.4em .6em;vertical-align:top}
        blockquote{margin:1em 0;padding-left:20px;border-left:2px solid var(--fg);color:var(--muted)}
        h1,h2,h3,h4,h5,h6,p.doc-subtitle{margin:1.1em 0 .4em;line-height:1.25;color:var(--fg)}
        h1:first-child{margin-top:0}
        h1{font-size:\(em("TITLE", 26));\(deco("TITLE", bold: false, italic: true, underline: false))}
        p.doc-subtitle{font-size:\(em("SUBTITLE", 15));\(deco("SUBTITLE", bold: false, italic: true, underline: false))color:var(--muted)}
        h2{font-size:\(em("HEADING_1", 20));\(deco("HEADING_1", bold: true, italic: true, underline: true))padding-left:14px;border-left:4px solid #434343}
        h3{font-size:\(em("HEADING_2", 16));\(deco("HEADING_2", bold: true, italic: false, underline: false))}
        h4{font-size:\(em("HEADING_3", 14));\(deco("HEADING_3", bold: true, italic: true, underline: false))}
        h5{font-size:\(em("HEADING_4", 12));\(deco("HEADING_4", bold: false, italic: true, underline: false))}
        h6{font-size:\(em("HEADING_5", 11));\(deco("HEADING_5", bold: false, italic: false, underline: false))}
        h6.heading-6{font-size:\(em("HEADING_6", 11));\(deco("HEADING_6", bold: false, italic: false, underline: false))}
        /* Resaltados de Docs: mismo tono, calmado, con subrayado del mismo color. */
        mark{color:inherit;padding:0 2px;border-radius:2px;background:transparent}
        mark.tone-yellow{background:rgba(255,243,155,var(--tint));box-shadow:inset 0 -2px 0 #e8d95a}
        mark.tone-cyan{background:rgba(189,247,255,var(--tint));box-shadow:inset 0 -2px 0 #7fd4e0}
        mark.tone-lime{background:rgba(221,255,116,var(--tint));box-shadow:inset 0 -2px 0 #b5d94a}
        mark.tone-lavender{background:rgba(217,216,255,var(--tint));box-shadow:inset 0 -2px 0 #a9a7e6}
        mark.tone-subtitle,mark.tone-peach{background:rgba(243,215,182,var(--tint));box-shadow:inset 0 -2px 0 #dcb083}
        mark.tone-pink{background:rgba(255,210,216,var(--tint));box-shadow:inset 0 -2px 0 #e59aa5}
        mark.tone-title{background:rgba(203,255,215,var(--tint));box-shadow:inset 0 -2px 0 #8fdca4}
        h2 mark,h2 mark[style]{background:transparent!important;box-shadow:none}
        h2 span[style],h1 span[style]{color:inherit!important}
        \(dark ? "span[style*='color:#000000'],span[style*='color:#242323'],span[style*='color:#272727'],span[style*='color:#434343']{color:inherit!important} mark[style]{background:rgba(255,255,255,.12)!important}" : "")
        .align-center{text-align:center}
        """
        return """
        <!doctype html><html lang="es"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <title>\(title)</title><style>\(css)</style></head>
        <body class="\(preach ? "preach" : "")"><article>\(body)</article></body></html>
        """
    }

    static let bridgeJS = """
    (function(){
      var send=function(m){try{window.webkit.messageHandlers.lector.postMessage(m)}catch(e){}};
      var t;function prog(){var h=document.documentElement;var max=h.scrollHeight-window.innerHeight;var p=max>0?window.scrollY/max:1;send({type:'progress',p:Math.max(0,Math.min(1,p))})}
      window.addEventListener('scroll',function(){clearTimeout(t);t=setTimeout(prog,150)},{passive:true});
      var last=0,pend;
      document.addEventListener('click',function(e){
        if(e.target.closest && e.target.closest('a')) return;
        var now=Date.now();
        if(now-last<300){clearTimeout(pend);send({type:'doubletap'});last=0;return}
        last=now;var y=e.clientY,h=window.innerHeight;
        pend=setTimeout(function(){send({type:'tap',y:y,h:h})},320);
      });
      window.__lectorRestore=function(p){var h=document.documentElement;var max=h.scrollHeight-window.innerHeight;window.scrollTo(0,max*p);setTimeout(prog,50)};
      window.__lectorPage=function(dir){window.scrollBy({top:dir*window.innerHeight*0.85,left:0,behavior:'smooth'});setTimeout(prog,400)};
      setTimeout(prog,300);
    })();
    """
}
