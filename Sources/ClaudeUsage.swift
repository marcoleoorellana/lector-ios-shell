import UIKit
import Security

/// Port del widget "Claude · uso" (Scriptable / Windows) a UIKit: mismos endpoints, mismo pace y mismos cortes.
enum Keychain {
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "lector",
                                kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ key: String, _ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "lector", kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let v = value, let d = v.data(using: .utf8) else { return }
        var add = base; add[kSecValueData as String] = d
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

struct UsageLimit {
    let label: String
    let percent: Double?
    let reset: Date?
    let window: TimeInterval?
    var elapsed: Double? {
        guard let w = window, let r = reset else { return nil }
        return max(0, min(1, 1 - r.timeIntervalSinceNow / w)) * 100
    }
    var pace: Double? { guard let p = percent, let e = elapsed else { return nil }; return p - e }
    enum Tier { case safe, warn, crit, none }
    var tier: Tier {
        guard let p = percent else { return .none }
        if p >= 90 { return .crit }
        guard let pc = pace else { return p < 50 ? .safe : (p < 80 ? .warn : .crit) }
        return pc > 15 ? .crit : (pc > 3 ? .warn : .safe)
    }
    var paceText: String {
        guard let pc = pace else { return "" }
        if pc > 3 { return "▲ \(Int(pc.rounded())) pts adelantado" }
        if pc < -3 { return "▼ \(Int((-pc).rounded())) pts de colchón" }
        return "en ritmo"
    }
    var resetText: String {
        guard let r = reset else { return "" }
        let m = Int((r.timeIntervalSinceNow / 60).rounded())
        if m < 0 { return "reiniciando" }
        if m < 60 { return "reinicia en \(m)m" }
        let h = m / 60
        if h < 24 { return String(format: "reinicia en %dh %02dm", h, m % 60) }
        let f = DateFormatter(); f.locale = Locale(identifier: "es_AR"); f.dateFormat = "EEE HH:mm"
        return "reinicia " + f.string(from: r)
    }
}

enum ClaudeAPI {
    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    enum Err: LocalizedError {
        case noKey, expired, blocked, http(Int), shape
        var errorDescription: String? {
            switch self {
            case .noKey: return "Pegá tu sessionKey de claude.ai"
            case .expired: return "Sesión vencida: pegá un sessionKey nuevo"
            case .blocked: return "Cloudflare bloqueó el pedido"
            case .http(let c): return "HTTP \(c)"
            case .shape: return "Respuesta inesperada"
            }
        }
    }

    /// El uuid se interpola en la URL: solo hex y guiones (viene del Keychain o de la API).
    static func validOrg(_ s: String) -> Bool {
        return !s.isEmpty && s.count <= 64 && s.range(of: "^[0-9a-fA-F-]+$", options: .regularExpression) != nil
    }

    private static func get(_ path: String, key: String, completion: @escaping (Result<Any, Error>) -> Void) {
        guard let url = URL(string: "https://claude.ai/api" + path) else {
            completion(.failure(URLError(.badURL))); return
        }
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        req.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        req.setValue("sessionKey=" + key, forHTTPHeaderField: "Cookie")
        req.httpShouldHandleCookies = false
        URLSession(configuration: .ephemeral).dataTask(with: req) { data, resp, error in
            if let e = error { completion(.failure(e)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { Keychain.set("claudeSessionKey", nil); completion(.failure(Err.expired)); return }
            if code == 403 { completion(.failure(Err.blocked)); return }
            guard code == 200, let d = data, let obj = try? JSONSerialization.jsonObject(with: d) else { completion(.failure(Err.http(code))); return }
            completion(.success(obj))
        }.resume()
    }

    static func fetch(completion: @escaping (Result<[UsageLimit], Error>) -> Void) {
        guard let key = Keychain.get("claudeSessionKey"), !key.isEmpty else { completion(.failure(Err.noKey)); return }
        let done: (Result<[UsageLimit], Error>) -> Void = { r in DispatchQueue.main.async { completion(r) } }
        func usage(org: String) {
            get("/organizations/\(org)/usage", key: key) { r in
                switch r {
                case .failure(let e): done(.failure(e))
                case .success(let obj): done(.success(parse(obj)))
                }
            }
        }
        if let org = Keychain.get("claudeOrgUuid"), validOrg(org) { usage(org: org); return }
        get("/organizations", key: key) { r in
            switch r {
            case .failure(let e): done(.failure(e))
            case .success(let obj):
                guard let arr = obj as? [[String: Any]], let first = arr.first,
                      let uuid = (first["uuid"] ?? first["id"]) as? String, validOrg(uuid) else { done(.failure(Err.shape)); return }
                Keychain.set("claudeOrgUuid", uuid)
                usage(org: uuid)
            }
        }
    }

    /// Acepta las dos formas vistas: `limits: [...]` (widget iOS) o claves `five_hour`/`seven_day…` (widget Windows).
    static func parse(_ obj: Any) -> [UsageLimit] {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        func date(_ v: Any?) -> Date? { guard let s = v as? String else { return nil }; return iso.date(from: s) ?? iso2.date(from: s) }
        func num(_ v: Any?) -> Double? { if let n = v as? NSNumber { return n.doubleValue }; return nil }
        var out: [(Int, UsageLimit)] = []
        guard let dict = obj as? [String: Any] else { return [] }
        if let limits = dict["limits"] as? [[String: Any]] {
            for l in limits {
                let kind = (l["kind"] as? String ?? ""), group = (l["group"] as? String ?? "")
                let model = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                var label: String, win: TimeInterval?, rank: Int
                if group == "session" || kind == "session" { label = "Límite de 5 horas"; win = 5 * 3600; rank = 0 }
                else if let m = model { label = "Semanal · " + m; win = 7 * 86400; rank = 2 }
                else if kind == "weekly_all" || group == "weekly" { label = "Semanal · todos"; win = 7 * 86400; rank = 1 }
                else { label = kind.replacingOccurrences(of: "_", with: " "); win = nil; rank = 3 }
                out.append((rank, UsageLimit(label: label, percent: num(l["percent"]), reset: date(l["resets_at"]), window: win)))
            }
        } else {
            let known: [(String, String, TimeInterval, Int)] = [
                ("five_hour", "Límite de 5 horas", 5 * 3600, 0),
                ("seven_day", "Semanal · todos", 7 * 86400, 1),
                ("seven_day_fable", "Semanal · Fable", 7 * 86400, 2),
                ("seven_day_opus", "Semanal · Opus", 7 * 86400, 2),
                ("seven_day_sonnet", "Semanal · Sonnet", 7 * 86400, 2)
            ]
            for (k, label, win, rank) in known {
                guard let b = dict[k] as? [String: Any] else { continue }
                var pct = num(b["utilization"]) ?? num(b["used_percentage"]) ?? num(b["percentage"])
                if let p = pct, p <= 1.0, p > 0 { pct = p * 100 }
                out.append((rank, UsageLimit(label: label, percent: pct, reset: date(b["resets_at"]), window: win)))
            }
        }
        return out.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}

/// Pantalla "Claude": los límites con %, ritmo y reinicio, en el mismo lenguaje visual del Lector.
final class ClaudeViewController: UIViewController {
    /// Las barras son frames dentro de vistas de autolayout: se recalculan en cada layout, no una sola vez.
    private struct Bar { let track: UIView; let fill: UIView; let marker: UIView; let limit: UsageLimit }
    private let stack = UIStackView()
    private let status = UILabel()
    private var pal: Palette { return Settings.shared.palette }
    private var timer: Timer?
    private var bars: [Bar] = []
    private var limits: [UsageLimit] = []
    private var errorText: String?
    private var updatedAt: Date?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Claude"
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "sessionKey", style: .plain, target: self, action: #selector(askKey))
        view.backgroundColor = pal.bg
        stack.axis = .vertical; stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        status.font = Fonts.mono(12); status.textColor = pal.secondary; status.numberOfLines = 0
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.refreshControl = UIRefreshControl()
        scroll.refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.reload() }
    }
    deinit { timer?.invalidate() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layoutIfNeeded()
        for b in bars {
            let w = b.track.bounds.width
            b.fill.frame = CGRect(x: 0, y: 0, width: w * CGFloat((b.limit.percent ?? 0) / 100), height: 4)
            if let e = b.limit.elapsed {
                b.marker.frame = CGRect(x: w * CGFloat(e / 100) - 1, y: -4, width: 2, height: 12)
            } else { b.marker.frame = .zero }
        }
    }

    @objc private func applyTheme() {
        view.backgroundColor = pal.bg
        navigationController?.navigationBar.barTintColor = pal.bg
        navigationController?.navigationBar.tintColor = pal.text
        navigationController?.navigationBar.largeTitleTextAttributes = [.foregroundColor: pal.text, .font: Fonts.ui(34, weight: .bold)]
        navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: pal.text, .font: Fonts.ui(17, weight: .semibold)]
        navigationController?.navigationBar.barStyle = Settings.shared.theme == .dark ? .black : .default
        (view.subviews.first as? UIScrollView)?.refreshControl?.tintColor = pal.secondary
        render()
    }

    @objc private func reload() {
        ClaudeAPI.fetch { [weak self] r in
            guard let self = self else { return }
            (self.view.subviews.first as? UIScrollView)?.refreshControl?.endRefreshing()
            switch r {
            case .failure(let e):
                self.limits = []; self.errorText = e.localizedDescription
                self.render()
                if case ClaudeAPI.Err.noKey = e { self.askKey() }
            case .success(let limits):
                self.limits = limits; self.errorText = nil; self.updatedAt = Date()
                self.render()
            }
        }
    }

    private func render() {
        bars.removeAll()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        status.textColor = pal.secondary
        for l in limits { stack.addArrangedSubview(row(l)) }
        if let e = errorText {
            status.text = e
        } else if let d = updatedAt {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            status.text = "actualizado \(f.string(from: d)) · tirá para refrescar"
        } else {
            status.text = ""
        }
        stack.addArrangedSubview(status)
        view.setNeedsLayout()
    }

    private func color(_ t: UsageLimit.Tier) -> UIColor {
        switch t {
        case .safe: return pal.text
        case .warn: return UIColor(red: 0.88, green: 0.64, blue: 0.31, alpha: 1)
        case .crit: return UIColor(red: 0.88, green: 0.38, blue: 0.30, alpha: 1)
        case .none: return pal.secondary
        }
    }

    private func row(_ l: UsageLimit) -> UIView {
        let label = UILabel(); label.font = Fonts.mono(12); label.textColor = pal.secondary
        Fonts.tracked(label, l.label.uppercased())
        let pct = UILabel(); pct.text = l.percent.map { "\(Int($0.rounded()))%" } ?? "—"
        pct.font = Fonts.tabular(44, weight: .bold); pct.textColor = color(l.tier)
        // Piso de ancho: si Figtree no trae numerales tabulares, el "ritmo" de al lado igual no salta.
        pct.setContentHuggingPriority(.required, for: .horizontal)
        pct.widthAnchor.constraint(greaterThanOrEqualToConstant: 118).isActive = true
        let pace = UILabel(); pace.text = l.paceText; pace.font = Fonts.ui(15); pace.textColor = pal.secondary
        let reset = UILabel(); reset.text = l.resetText; reset.font = Fonts.mono(13); reset.textColor = pal.secondary; reset.textAlignment = .right
        let top = UIStackView(arrangedSubviews: [pct, pace]); top.axis = .horizontal; top.alignment = .lastBaseline; top.spacing = 14
        let track = UIView(); track.backgroundColor = pal.hairline; track.translatesAutoresizingMaskIntoConstraints = false
        track.heightAnchor.constraint(equalToConstant: 4).isActive = true
        let fill = UIView(); fill.backgroundColor = color(l.tier); track.addSubview(fill)
        let marker = UIView(); marker.backgroundColor = pal.text; track.addSubview(marker)
        let container = UIStackView(arrangedSubviews: [label, top, track, reset]); container.axis = .vertical; container.spacing = 8
        bars.append(Bar(track: track, fill: fill, marker: marker, limit: l))
        return container
    }

    @objc private func askKey() {
        let a = UIAlertController(title: "sessionKey de claude.ai", message: "Queda en el Keychain de este iPad. Nunca sale del dispositivo.", preferredStyle: .alert)
        a.addTextField { $0.isSecureTextEntry = true; $0.placeholder = "sk-ant-sid…" }
        a.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        a.addAction(UIAlertAction(title: "Guardar", style: .default) { _ in
            let v = a.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !v.isEmpty { Keychain.set("claudeSessionKey", v); Keychain.set("claudeOrgUuid", nil); self.reload() }
        })
        present(a, animated: true)
    }
}
