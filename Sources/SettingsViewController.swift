import UIKit

final class SettingsViewController: UITableViewController, UITextFieldDelegate {
    private var pal: Palette { return Settings.shared.palette }
    private let sections: [(String, [String])] = [
        ("Lectura", ["Tamaño del texto", "Interlineado", "Como en Docs", "Tema"]),
        ("Contenido", ["Origen (URL)", "Actualizar ahora"]),
        ("Seguridad", ["PIN al abrir", "Touch ID", "Cambiar PIN"]),
        ("Estado", ["Batería"]),
        ("Acerca", ["Versión"])
    ]

    init() {
        super.init(style: .grouped)
        // El formSheet de iPad mide 540x620 por defecto y cortaba las ultimas secciones.
        preferredContentSize = CGSize(width: 620, height: 820)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Ajustes"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Listo", style: .done, target: self, action: #selector(close))
        tableView.rowHeight = 56
        tableView.separatorColor = pal.hairline
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
    }

    @objc private func applyTheme() {
        view.backgroundColor = pal.bg; tableView.backgroundColor = pal.bg
        navigationController?.navigationBar.barTintColor = pal.bg
        navigationController?.navigationBar.tintColor = pal.text
        navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: pal.text, .font: Fonts.ui(17, weight: .semibold)]
        tableView.reloadData()
    }

    @objc private func close() { dismiss(animated: true) }

    override func numberOfSections(in tableView: UITableView) -> Int { return sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return sections[section].1.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { return sections[section].0.uppercased() }
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        if let h = view as? UITableViewHeaderFooterView { h.textLabel?.font = Fonts.mono(12); h.textLabel?.textColor = pal.secondary }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let name = sections[indexPath.section].1[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = pal.bg
        cell.textLabel?.text = name; cell.textLabel?.font = Fonts.ui(17); cell.textLabel?.textColor = pal.text
        cell.detailTextLabel?.font = Fonts.mono(14); cell.detailTextLabel?.textColor = pal.secondary
        cell.selectionStyle = .none
        let s = Settings.shared
        switch name {
        case "Tamaño del texto":
            cell.detailTextLabel?.text = "\(Int((s.textScale * 100).rounded())) %"
            cell.accessoryView = slider(value: Float(s.textScale), min: 0.6, max: 2.0, action: #selector(fontSizeChanged(_:)))
        case "Interlineado":
            cell.detailTextLabel?.text = "\(Int((s.leadingScale * 100).rounded())) %"
            cell.accessoryView = slider(value: Float(s.leadingScale), min: 0.7, max: 1.6, action: #selector(lineHeightChanged(_:)))
        case "Como en Docs":
            cell.selectionStyle = .default
            cell.detailTextLabel?.text = "Vuelve tamaño e interlineado al 100 %, tal cual Google Docs"
        case "Tamaño en predicación":
            cell.accessoryView = slider(value: Float(s.preachFontSize), min: 20, max: 40, action: #selector(preachSizeChanged(_:)))
        case "Tema":
            let seg = UISegmentedControl(items: ["Claro", "Sepia"])
            seg.selectedSegmentIndex = [ThemeMode.light, .sepia].firstIndex(of: s.theme) ?? 0
            seg.tintColor = pal.text
            seg.addTarget(self, action: #selector(themeChanged(_:)), for: .valueChanged)
            cell.accessoryView = seg
        case "Origen (URL)":
            let tf = UITextField(frame: CGRect(x: 0, y: 0, width: 340, height: 34))
            tf.text = s.contentBaseURL; tf.placeholder = "https://…/lite-reader"; tf.font = Fonts.mono(14)
            tf.textColor = pal.text; tf.textAlignment = .right; tf.keyboardType = .URL
            tf.autocapitalizationType = .none; tf.autocorrectionType = .no; tf.returnKeyType = .done; tf.delegate = self
            cell.accessoryView = tf
        case "Actualizar ahora":
            cell.selectionStyle = .default
            if let d = s.lastSync { let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"; cell.detailTextLabel?.text = f.string(from: d) }
            else { cell.detailTextLabel?.text = "nunca" }
        case "PIN al abrir":
            cell.accessoryView = toggle(s.pinEnabled, action: #selector(pinToggled(_:)))
        case "Touch ID":
            cell.accessoryView = toggle(s.touchIDEnabled, action: #selector(touchToggled(_:)))
        case "Cambiar PIN":
            cell.selectionStyle = .default; cell.accessoryType = .disclosureIndicator
        case "Batería":
            cell.selectionStyle = .default
            cell.textLabel?.text = Battery.summary(); cell.textLabel?.font = Fonts.mono(13); cell.textLabel?.numberOfLines = 2
        case "Versión":
            let v = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
            cell.detailTextLabel?.text = "Lector 2.0 (\(v)) · iOS \(UIDevice.current.systemVersion)"
        default: break
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].1[indexPath.row] {
        case "Actualizar ahora":
            toast("Actualizando…")
            ContentStore.shared.refresh { r in
                switch r {
                case .success(let n): self.toast(n == 0 ? "Sin cambios" : "\(n) documento(s) actualizados"); self.tableView.reloadData()
                case .failure(let e): self.toast(e.localizedDescription)
                }
            }
        case "Como en Docs":
            Settings.shared.resetTypography(); tableView.reloadSections(IndexSet(integer: 0), with: .none); toast("Como en Google Docs")
        case "Batería":
            tableView.reloadRows(at: [indexPath], with: .none)
        case "Cambiar PIN":
            let vc = PinViewController(mode: .set) { [weak self] in self?.toast("PIN actualizado") }
            present(UINavigationController(rootViewController: vc), animated: true)
        default: break
        }
    }

    private func slider(value: Float, min: Float, max: Float, action: Selector) -> UISlider {
        let sl = UISlider(frame: CGRect(x: 0, y: 0, width: 220, height: 34))
        sl.minimumValue = min; sl.maximumValue = max; sl.value = value
        // La perilla iba pintada del color del fondo: quedaba invisible y el control parecia una raya.
        sl.tintColor = pal.text; sl.thumbTintColor = pal.text
        sl.addTarget(self, action: action, for: .valueChanged)
        return sl
    }
    private func toggle(_ on: Bool, action: Selector) -> UISwitch {
        let sw = UISwitch(); sw.isOn = on; sw.onTintColor = pal.text; sw.addTarget(self, action: action, for: .valueChanged); return sw
    }

    @objc private func fontSizeChanged(_ s: UISlider) { Settings.shared.textScale = Double((s.value * 20).rounded() / 20); reloadLectura() }
    @objc private func lineHeightChanged(_ s: UISlider) { Settings.shared.leadingScale = Double((s.value * 20).rounded() / 20); reloadLectura() }
    private func reloadLectura() {
        for (i, row) in sections[0].1.enumerated() where row == "Tamaño del texto" || row == "Interlineado" {
            if let cell = tableView.cellForRow(at: IndexPath(row: i, section: 0)) {
                let s = Settings.shared
                cell.detailTextLabel?.text = "\(Int(((row == "Tamaño del texto" ? s.textScale : s.leadingScale) * 100).rounded())) %"
            }
        }
    }
    @objc private func preachSizeChanged(_ s: UISlider) { Settings.shared.preachFontSize = Double(s.value.rounded()) }
    @objc private func themeChanged(_ s: UISegmentedControl) { Settings.shared.theme = [ThemeMode.light, .sepia][s.selectedSegmentIndex] }
    @objc private func pinToggled(_ s: UISwitch) { Settings.shared.pinEnabled = s.isOn }
    @objc private func touchToggled(_ s: UISwitch) { Settings.shared.touchIDEnabled = s.isOn }

    func textFieldDidEndEditing(_ textField: UITextField) { Settings.shared.contentBaseURL = textField.text ?? "" }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
}
