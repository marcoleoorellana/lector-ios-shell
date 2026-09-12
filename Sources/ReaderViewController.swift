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
    private var preachStarted = Date.distantPast
    private var torndown = false
    /// El primer reporte del bridge llega con scrollY=0 y pisaría el progreso guardado: se ignora hasta que restauramos o el usuario toca.
    private var ignoreProgressUntil = Date.distantPast
    private var userInteracted = false
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
        // Translucido solo mientras carga, para que se vea el fondo del tema en vez de blanco.
        // En cuanto hay contenido pasa a opaco: con la vista translucida el compositor mezcla
        // con alfa los 3,1 MP de la pantalla Retina en cada cuadro, y en el A7 eso es lo que
        // hace que el scroll se sienta pesado y gaste bateria de mas.
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
        // Tocar la etiqueta de la esquina también sale de predicación (el doble toque no es obvio).
        preachLabel.isUserInteractionEnabled = true
        preachLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(togglePreach)))
        view.addSubview(preachLabel)
        NSLayoutConstraint.activate([
            preachLabel.topAnchor.constraint(equalTo: progressTrack.bottomAnchor, constant: 12),
            preachLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pushCSSVars), name: .typographyChanged, object: nil)
        progress = ContentStore.shared.progress(for: doc.id)
        applyTheme()
        ignoreProgressUntil = Date().addingTimeInterval(0.8)
        load()
        startTimer()
    }

    /// Leyendo alcanza con refrescar de a poco; el segundero solo hace falta como cronometro de
    /// predicacion. A 1 Hz permanente el CPU nunca baja a reposo profundo y se nota en la bateria.
    private func startTimer() {
        timer?.invalidate()
        // Un segundo en los dos modos: es una etiqueta nativa, cuesta nada, y el usuario
        // quiere VER que el reloj se mueve tambien leyendo.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateStatus() }
        timer?.tolerance = 0.1
        updateStatus()
    }

    /// El userContentController retiene al handler: hay que soltarlo al salir, no solo en deinit.
    private func teardown() {
        guard !torndown else { return }
        torndown = true
        timer?.invalidate(); timer = nil
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "lector")
    }

    deinit { teardown() }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationController?.navigationBar.sizeToFit()
        pushCSSVars()
        keepAwake()
    }

    // MARK: pantalla despierta mientras se lee, pero no para siempre
    // Sin tocar nada durante 20 min se devuelve el control al bloqueo automatico de iOS:
    // un documento que quedo abierto no puede vaciar la bateria de noche.
    private static let despiertoMinutos: TimeInterval = 20 * 60
    private var awakeTimer: Timer?
    private func keepAwake() {
        UIApplication.shared.isIdleTimerDisabled = true
        awakeTimer?.invalidate()
        awakeTimer = Timer.scheduledTimer(withTimeInterval: ReaderViewController.despiertoMinutos, repeats: false) { _ in
            UIApplication.shared.isIdleTimerDisabled = false
        }
        awakeTimer?.tolerance = 60
    }
    private func letSleep() {
        awakeTimer?.invalidate(); awakeTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            letSleep()
            exitPreachIfNeeded()
            navigationController?.navigationBar.prefersLargeTitles = true
            teardown()
        }
    }

    // Leyendo no hace falta ver hora, fecha ni bateria: la barra de estado va escondida siempre.
    override var prefersStatusBarHidden: Bool { return true }
    override var prefersHomeIndicatorAutoHidden: Bool { return preaching }

    private func load() {
        let html = ReaderHTML.wrap(body: ContentStore.shared.html(for: doc), title: doc.title,
                                   styles: ContentStore.shared.styles, settings: Settings.shared, preach: preaching)
        webView.loadHTMLString(html, baseURL: ContentStore.shared.baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Ya hay contenido pintado: se puede componer opaco sin riesgo de destello.
        webView.isOpaque = true
        if debugPreach && !preaching { debugPreach = false; togglePreach() }
        let p = ContentStore.shared.progress(for: doc.id)
        // También se restaura el final (p ≥ 0.97): un doc terminado se abre donde quedó, no arriba.
        ignoreProgressUntil = Date().addingTimeInterval(0.8)
        if p > 0.01 { webView.evaluateJavaScript("window.__lectorRestore(\(p))", completionHandler: nil) }
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
            if (body["touched"] as? Bool) == true { userInteracted = true; keepAwake() }
            // Sin interacción: ni el reporte inicial ni un doc más corto que el viewport pueden tocar el progreso.
            guard userInteracted || Date() >= ignoreProgressUntil else { return }
            let maxScroll = (body["max"] as? Double) ?? 1
            guard maxScroll > 0 || userInteracted else { return }
            progress = (body["p"] as? Double) ?? 0
            ContentStore.shared.setProgress(progress, for: doc.id)
            updateStatus()
        case "tap":
            keepAwake()
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
        // Los primeros 10 s de predicación se indica cómo salir; después queda solo el reloj.
        let hint = (preaching && Date().timeIntervalSince(preachStarted) < 10) ? " · DOBLE TOQUE O TOCÁ ACÁ PARA SALIR" : ""
        preachLabel.text = "PREDICACIÓN · \(clock) · \(pct)\(hint)"
        let w = progressTrack.bounds.width * CGFloat(progress)
        progressFill.frame = CGRect(x: 0, y: 0, width: w, height: 2)
    }

    @objc private func applyTheme() {
        view.backgroundColor = pal.bg; webView.backgroundColor = pal.bg; webView.scrollView.backgroundColor = pal.bg
        progressTrack.backgroundColor = pal.hairline; progressFill.backgroundColor = pal.text
        statusLabel.textColor = pal.secondary; preachLabel.textColor = pal.secondary
        navigationController?.navigationBar.barTintColor = pal.bg
        navigationController?.navigationBar.tintColor = pal.text
        navigationController?.navigationBar.barStyle = .default
        pushCSSVars()
    }

    /// Cambios en vivo sin recargar: variables CSS.
    @objc private func pushCSSVars() {
        let s = Settings.shared
        let js = ReaderHTML.cssVarsJS(settings: s, preach: preaching)
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc private func togglePreach() {
        preaching.toggle()
        if preaching { preachStarted = Date() }
        updateStatus()
        navigationController?.setNavigationBarHidden(preaching, animated: true)
        startTimer()
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
        vc.preferredContentSize = CGSize(width: 320, height: 310)
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
    private let lhLabel = UILabel()
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

        let lhSmaller = UIButton(type: .system), lhBigger = UIButton(type: .system)
        lhSmaller.setTitle("≡", for: .normal); lhSmaller.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        lhBigger.setTitle("≡", for: .normal); lhBigger.titleLabel?.font = UIFont.systemFont(ofSize: 24)
        for b in [lhSmaller, lhBigger] { b.tintColor = pal.text; b.layer.borderWidth = 1; b.layer.borderColor = pal.hairline.cgColor; b.layer.cornerRadius = 8 }
        lhSmaller.addTarget(self, action: #selector(lhDec), for: .touchUpInside)
        lhBigger.addTarget(self, action: #selector(lhInc), for: .touchUpInside)
        lhLabel.font = Fonts.mono(13); lhLabel.textColor = pal.secondary; lhLabel.textAlignment = .center
        let lhRow = UIStackView(arrangedSubviews: [lhSmaller, lhLabel, lhBigger]); lhRow.axis = .horizontal; lhRow.distribution = .fillEqually; lhRow.spacing = 12
        lhRow.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let seg = UISegmentedControl(items: ["Claro", "Sepia"])
        seg.selectedSegmentIndex = [ThemeMode.light, .sepia].firstIndex(of: Settings.shared.theme) ?? 0
        seg.tintColor = pal.text
        seg.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)

        let reset = UIButton(type: .system)
        reset.setTitle("Como en Docs", for: .normal); reset.titleLabel?.font = Fonts.ui(15, weight: .medium)
        reset.tintColor = pal.text; reset.layer.borderWidth = 1; reset.layer.borderColor = pal.hairline.cgColor; reset.layer.cornerRadius = 8
        reset.heightAnchor.constraint(equalToConstant: 40).isActive = true
        reset.addTarget(self, action: #selector(resetDocs), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [sizeRow, lhRow, reset, seg]); stack.axis = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        refresh()
    }
    private func refresh() {
        let s = Settings.shared
        // Solo el numero: con "tamaño"/"interlineado" delante se cortaba ("tamaño 10…").
        sizeLabel.text = "\(Int((s.textScale * 100).rounded())) %"
        lhLabel.text = "\(Int((s.leadingScale * 100).rounded())) %"
    }
    @objc private func lhDec() { Settings.shared.leadingScale -= 0.05; refresh(); onChange() }
    @objc private func lhInc() { Settings.shared.leadingScale += 0.05; refresh(); onChange() }
    @objc private func dec() { Settings.shared.textScale -= 0.05; refresh(); onChange() }
    @objc private func inc() { Settings.shared.textScale += 0.05; refresh(); onChange() }
    @objc private func resetDocs() { Settings.shared.resetTypography(); refresh(); onChange() }
    @objc private func themeChanged(_ s: UISegmentedControl) {
        Settings.shared.theme = [ThemeMode.light, .sepia][s.selectedSegmentIndex]
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

    /// Las fuentes van embebidas como data URI: con `loadHTMLString` + baseURL file:// el WKWebView no puede leer subrecursos.
    /// Se arma una sola vez (≈190 KB de base64) y se reusa en cada documento.
    static let fontFaces: String = {
        let faces: [(String, Int, String)] = [
            ("Figtree-Regular", 400, "normal"),
            ("Figtree-RegularItalic", 400, "italic"),
            ("Figtree-Medium", 500, "normal"),
            ("Figtree-SemiBold", 600, "normal"),
            ("Figtree-SemiBoldItalic", 600, "italic"),
            ("Figtree-Bold", 700, "normal"),
            ("Figtree-BoldItalic", 700, "italic")
        ]
        var out = ""
        for (file, weight, style) in faces {
            guard let dir = Bundle.main.resourceURL,
                  let data = try? Data(contentsOf: dir.appendingPathComponent("fonts/\(file).ttf")) else { continue }
            out += "@font-face{font-family:Figtree;font-weight:\(weight);font-style:\(style);font-display:swap;"
            out += "src:url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype')}\n"
        }
        return out
    }()

    /// 12 pt de Docs = 12 pt fisicos en el iPad: 1 pt = 1/72 in y la pantalla tiene 132 px CSS por pulgada.
    static let pxPorPt = 132.0 / 72.0
    /// Interlineado "sencillo" (100 %) de Docs = la altura natural de la fuente, ~1.2 del cuerpo.
    static let lineaSencilla = 1.2

    static func basePx(_ styles: [String: [String: Any]], _ s: Settings) -> Double {
        return pt(styles, "NORMAL_TEXT", 11) * pxPorPt * s.textScale
    }

    static func cssVarsJS(settings s: Settings, preach: Bool) -> String {
        let pal = s.palette
        let base = basePx(ContentStore.shared.styles, s)
        let alpha = 1.0
        return """
        (function(){var r=document.documentElement.style;
        r.setProperty('--fs','\(base)px');r.setProperty('--lhk','\(lineaSencilla * s.leadingScale)');r.setProperty('--bg','\(pal.bgHex)');r.setProperty('--fg','\(pal.textHex)');
        r.setProperty('--muted','\(pal.secondaryHex)');r.setProperty('--line','\(pal.hairlineHex)');r.setProperty('--tint','\(alpha)');})();
        """
    }

    static func wrap(body: String, title: String, styles: [String: [String: Any]], settings s: Settings, preach: Bool) -> String {
        let pal = s.palette
        let normal = pt(styles, "NORMAL_TEXT", 11)
        // Metricas de parrafo de Docs: interlineado en % y espacio antes/despues en pt.
        func num(_ key: String, _ name: String, _ fb: Double) -> Double {
            if let v = styles[key]?[name] as? Double { return v }
            if let v = styles[key]?[name] as? Int { return Double(v) }
            return fb
        }
        /// line-height y margenes de un estilo, en funcion de --fs (asi Aa los escala a todos).
        func para(_ key: String, _ fbAbove: Double, _ fbBelow: Double) -> String {
            let lh = num(key, "lineSpacing", 100) / 100
            let above = num(key, "spaceAbovePt", fbAbove) / normal, below = num(key, "spaceBelowPt", fbBelow) / normal
            return String(format: "line-height:calc(var(--lhk)*%.3f);margin:calc(var(--fs)*%.3f) 0 calc(var(--fs)*%.3f);", lh, above, below)
        }
        // Escala: el texto normal de Docs (en pt) se ve a --fs px; los encabezados mantienen la proporción de Docs.
        func em(_ key: String, _ fb: Double) -> String {
            // Proporcion exacta de Google Docs (styles.json trae los pt reales de cada estilo).
            return String(format: "%.3fem", pt(styles, key, fb) / normal)
        }
        func deco(_ key: String, bold: Bool, italic: Bool, underline: Bool) -> String {
            let b = flag(styles, key, "bold", bold), i = flag(styles, key, "italic", italic), u = flag(styles, key, "underline", underline)
            return "font-weight:\(b ? 700 : 400);font-style:\(i ? "italic" : "normal");text-decoration:\(u ? "underline" : "none");"
        }
        let css = """
        \(fontFaces)
        :root{--fs:\(basePx(styles, s))px;--lhk:\(lineaSencilla * s.leadingScale);--bg:\(pal.bgHex);--fg:\(pal.textHex);--muted:\(pal.secondaryHex);--line:\(pal.hairlineHex);--tint:1}
        html{background:var(--bg);-webkit-text-size-adjust:100%}
        body{margin:0;padding:28px 0 120px;background:var(--bg);color:var(--fg);font-family:Figtree,-apple-system,Helvetica,sans-serif;font-size:var(--fs);line-height:calc(var(--lhk)*\(String(format: "%.3f", num("NORMAL_TEXT", "lineSpacing", 100) / 100)));-webkit-font-smoothing:antialiased;-webkit-tap-highlight-color:transparent;-webkit-hyphens:auto;hyphens:auto}
        article{max-width:640px;margin:0 auto;padding:0 32px}
        body.preach article{max-width:720px}
        p{\(para("NORMAL_TEXT", 0, 0))}
        p:empty,p.is-section-break,p.is-empty-line{margin:0;min-height:1.2em}
        li{margin:0 0 .15em}
        li>p{margin:0}
        ul,ol{margin:.2em 0 .6em;padding-left:1.25em}
        br+br{display:none}
        a{color:var(--fg)}
        img{max-width:100%;height:auto}
        table{border-collapse:collapse;width:100%;font-size:.9em}
        td,th{border:1px solid var(--line);padding:.4em .6em;vertical-align:top}
        blockquote{margin:1em 0;padding-left:20px;border-left:2px solid var(--fg);color:var(--muted)}
        h1,h2,h3,h4,h5,h6,p.doc-subtitle{color:var(--fg)}
        h1{\(para("TITLE", 0, 3))}
        p.doc-subtitle{\(para("SUBTITLE", 0, 16))}
        h2{\(para("HEADING_1", 20, 6))}
        h3{\(para("HEADING_2", 18, 6))}
        h4{\(para("HEADING_3", 16, 4))}
        h5{\(para("HEADING_4", 14, 4))}
        h6{\(para("HEADING_5", 12, 4))}
        h6.heading-6{\(para("HEADING_6", 12, 4))}
        h1:first-child{margin-top:0}
        h1{font-size:\(em("TITLE", 26));\(deco("TITLE", bold: false, italic: true, underline: false))}
        p.doc-subtitle{font-size:\(em("SUBTITLE", 15));\(deco("SUBTITLE", bold: false, italic: true, underline: false))}
        h2{font-size:\(em("HEADING_1", 20));\(deco("HEADING_1", bold: true, italic: true, underline: true))}
        h3{font-size:\(em("HEADING_2", 16));\(deco("HEADING_2", bold: true, italic: false, underline: false))}
        h4{font-size:\(em("HEADING_3", 14));\(deco("HEADING_3", bold: true, italic: true, underline: false))}
        h5{font-size:\(em("HEADING_4", 12));\(deco("HEADING_4", bold: false, italic: true, underline: false))}
        h6{font-size:\(em("HEADING_5", 11));\(deco("HEADING_5", bold: false, italic: false, underline: false))}
        h6.heading-6{font-size:\(em("HEADING_6", 11));\(deco("HEADING_6", bold: false, italic: false, underline: false))}
        /* Resaltados: los colores EXACTOS de los estilos del usuario en Google Docs
           (Titulo #acfdd0, Subtitulo #fdd3a7, Enc.1 #434343 con texto claro, Enc.2 #97fffc,
           Enc.3 #d0ff7d, Enc.4 #ffb2b2, Enc.5 #d8d0ff, Enc.6 #fff399). Sin subrayado: en Docs
           el resaltado es solo el fondo. --tint permite aguarlos; 1 = tal cual Docs. */
        mark{color:inherit;padding:0 3px;border-radius:2px;background:transparent}
        mark.tone-yellow{background:rgba(255,243,153,var(--tint))}
        mark.tone-cyan{background:rgba(151,255,252,var(--tint))}
        mark.tone-lime{background:rgba(208,255,125,var(--tint))}
        mark.tone-lavender{background:rgba(216,208,255,var(--tint))}
        mark.tone-subtitle,mark.tone-peach{background:rgba(253,211,167,var(--tint))}
        mark.tone-pink{background:rgba(255,178,178,var(--tint))}
        mark.tone-title{background:rgba(172,253,208,var(--tint))}
        /* Encabezado 1 en Docs: caja gris oscura con texto claro. */
        h2 mark,h2 mark[style]{background:#434343!important;color:#d0e0e3;padding:0 8px}
        h2 span[style],h1 span[style]{color:inherit!important}
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
      var touched=false;
      document.addEventListener('touchstart',function(){touched=true},{passive:true});
      var t;function prog(){var h=document.documentElement;var max=h.scrollHeight-window.innerHeight;var p=max>0?window.scrollY/max:1;send({type:'progress',p:Math.max(0,Math.min(1,p)),max:max,touched:touched})}
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
