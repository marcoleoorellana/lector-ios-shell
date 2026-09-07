import UIKit
import LocalAuthentication
import CommonCrypto

enum Pin {
    static func hash(_ pin: String) -> String {
        let data = Array(("lector:" + pin).utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(data, CC_LONG(data.count), &digest)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Pantalla de PIN. Modo .unlock (verifica) o .set (pide dos veces y guarda).
final class PinViewController: UIViewController {
    enum Mode { case unlock, set }
    private let mode: Mode
    private let onDone: () -> Void
    private var entered = ""
    private var firstEntry: String?
    private var wrongTries = 0
    private var lockedUntil: Date?
    private var isLocked: Bool { if let u = lockedUntil, Date() < u { return true }; return false }
    private let dots = UIStackView()
    private let subtitle = UILabel()
    private var pal: Palette { return Settings.shared.palette }

    init(mode: Mode, onDone: @escaping () -> Void) {
        self.mode = mode; self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = pal.bg

        let title = UILabel()
        title.text = "Lector"; title.font = Fonts.ui(22, weight: .semibold); title.textColor = pal.text; title.textAlignment = .center
        subtitle.text = mode == .unlock ? "Ingresá el PIN" : "Elegí un PIN nuevo"
        subtitle.font = Fonts.ui(15); subtitle.textColor = pal.secondary; subtitle.textAlignment = .center

        dots.axis = .horizontal; dots.spacing = 18; dots.alignment = .center
        for _ in 0..<6 {
            let v = UIView(); v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: 14).isActive = true
            v.heightAnchor.constraint(equalToConstant: 14).isActive = true
            v.layer.cornerRadius = 7; v.layer.borderWidth = 1; v.layer.borderColor = pal.text.cgColor
            dots.addArrangedSubview(v)
        }
        renderDots()

        let grid = UIStackView(); grid.axis = .vertical; grid.spacing = 24
        let rows: [[String]] = [["1","2","3"],["4","5","6"],["7","8","9"],["touch","0","del"]]
        for r in rows {
            let row = UIStackView(); row.axis = .horizontal; row.spacing = 24
            for key in r { row.addArrangedSubview(makeKey(key)) }
            grid.addArrangedSubview(row)
        }

        let foot = UILabel()
        foot.text = mode == .unlock && Settings.shared.touchIDEnabled ? "Touch ID activado · el PIN nunca sale del iPad" : "El PIN nunca sale del iPad"
        foot.font = Fonts.mono(12); foot.textColor = pal.secondary; foot.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [title, subtitle, dots, grid, foot])
        stack.axis = .vertical; stack.alignment = .center; stack.spacing = 32
        stack.setCustomSpacing(12, after: title)
        stack.setCustomSpacing(48, after: subtitle)
        stack.setCustomSpacing(48, after: dots)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        if mode == .set {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancelar", style: .plain, target: self, action: #selector(cancel))
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if mode == .unlock && Settings.shared.touchIDEnabled { tryBiometrics() }
    }

    private func makeKey(_ key: String) -> UIView {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 88).isActive = true
        b.heightAnchor.constraint(equalToConstant: 88).isActive = true
        b.layer.cornerRadius = 44
        b.tintColor = pal.text
        switch key {
        case "touch":
            b.setTitle(mode == .unlock && Settings.shared.touchIDEnabled ? "ID" : "", for: .normal)
            b.titleLabel?.font = Fonts.ui(17, weight: .semibold)
            b.addTarget(self, action: #selector(tryBiometrics), for: .touchUpInside)
        case "del":
            b.setTitle("⌫", for: .normal); b.titleLabel?.font = UIFont.systemFont(ofSize: 26)
            b.addTarget(self, action: #selector(backspace), for: .touchUpInside)
        default:
            b.setTitle(key, for: .normal); b.titleLabel?.font = Fonts.ui(30)
            b.layer.borderWidth = 1; b.layer.borderColor = pal.hairline.cgColor
            b.addTarget(self, action: #selector(digit(_:)), for: .touchUpInside)
        }
        return b
    }

    private func renderDots() {
        for (i, v) in dots.arrangedSubviews.enumerated() {
            v.backgroundColor = i < entered.count ? pal.text : .clear
        }
    }

    @objc private func digit(_ sender: UIButton) {
        guard !isLocked, entered.count < 6, let t = sender.title(for: .normal) else { return }
        entered += t; renderDots()
        if entered.count == 6 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.submit() } }
    }
    @objc private func backspace() { if !entered.isEmpty { entered.removeLast(); renderDots() } }
    @objc private func cancel() { dismiss(animated: true) }

    private func submit() {
        switch mode {
        case .unlock:
            guard !isLocked else { entered = ""; renderDots(); return }
            if Pin.hash(entered) == Settings.shared.pinHash {
                wrongTries = 0; finish()
            } else {
                wrongTries += 1
                if wrongTries >= 5 { startCooldown() } else { reject("PIN incorrecto") }
            }
        case .set:
            if let first = firstEntry {
                if first == entered {
                    Settings.shared.pinHash = Pin.hash(entered)
                    finish()
                } else { firstEntry = nil; reject("No coinciden, empezá de nuevo") }
            } else {
                firstEntry = entered; entered = ""; renderDots(); subtitle.text = "Repetí el PIN"
            }
        }
    }

    /// Cinco fallos seguidos: 30 s sin aceptar nada (teclado y Touch ID).
    private func startCooldown() {
        wrongTries = 0
        lockedUntil = Date().addingTimeInterval(30)
        reject("Esperá 30 s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self else { return }
            self.lockedUntil = nil
            self.subtitle.text = "Ingresá el PIN"
        }
    }

    private func reject(_ msg: String) {
        subtitle.text = msg
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, -10, 10, -6, 6, 0]; a.duration = 0.35
        dots.layer.add(a, forKey: "shake")
        entered = ""; renderDots()
    }

    private func finish() {
        onDone()
        dismiss(animated: true)
    }

    @objc private func tryBiometrics() {
        guard mode == .unlock, !isLocked else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Desbloquear Lector") { ok, _ in
            if ok { DispatchQueue.main.async { self.finish() } }
        }
    }
}
