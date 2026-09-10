import UIKit

final class DocCell: UITableViewCell {
    let titleLabel = UILabel()
    let metaLabel = UILabel()
    let hairline = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.font = Fonts.ui(17, weight: .semibold); titleLabel.numberOfLines = 2
        metaLabel.font = Fonts.mono(13)
        let stack = UIStackView(arrangedSubviews: [titleLabel, metaLabel])
        stack.axis = .vertical; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        hairline.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack); contentView.addSubview(hairline)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            hairline.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            hairline.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            hairline.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ pal: Palette) {
        backgroundColor = pal.bg; contentView.backgroundColor = pal.bg
        titleLabel.textColor = pal.text; metaLabel.textColor = pal.secondary; hairline.backgroundColor = pal.hairline
    }
}

final class LibraryViewController: UITableViewController, UISearchResultsUpdating {
    private var all: [Doc] = []
    private var shown: [Doc] = []
    private let search = UISearchController(searchResultsController: nil)
    private let header = UIView()
    private let continueTitle = UILabel()
    private let continueMeta = UILabel()
    private let continueBar = UIView()
    private let continueFill = UIView()
    private var continueDoc: Doc?
    private let footer = UILabel()
    private var pal: Palette { return Settings.shared.palette }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Biblioteca"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        // "Actualizar" es EL boton de la app (en negrita, arriba a la derecha, donde cae el pulgar):
        // trae lo nuevo de Google Docs con un solo toque. Ajustes queda a la izquierda.
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Actualizar", style: .done,
                                                            target: self, action: #selector(tapRefresh))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Ajustes", style: .plain,
                                                           target: self, action: #selector(openSettings))

        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Buscar en tus documentos"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.register(DocCell.self, forCellReuseIdentifier: "doc")
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 84

        buildHeader()
        footer.font = Fonts.mono(12); footer.textAlignment = .left
        footer.frame = CGRect(x: 0, y: 0, width: 0, height: 64)
        tableView.tableFooterView = footer

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .contentChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeChanged, object: nil)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
        applyTheme()
        updateContinue()
        tableView.reloadData()
    }

    private var debugOpened = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Depuración: Documents/snap.open con un id de doc abre ese documento (y snap.preach entra en predicación).
        guard !debugOpened else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Depuración: Documents/snap.sync equivale a tocar "Actualizar" (para capturar el banner).
        if FileManager.default.fileExists(atPath: docs.appendingPathComponent("snap.sync").path) {
            debugOpened = true; try? FileManager.default.removeItem(at: docs.appendingPathComponent("snap.sync"))
            tapRefresh(); return
        }
        if let id = try? String(contentsOf: docs.appendingPathComponent("snap.open"), encoding: .utf8),
           let doc = ContentStore.shared.doc(id: id.trimmingCharacters(in: .whitespacesAndNewlines)) {
            debugOpened = true
            let r = ReaderViewController(doc: doc)
            r.debugPreach = FileManager.default.fileExists(atPath: docs.appendingPathComponent("snap.preach").path)
            navigationController?.pushViewController(r, animated: true)
        }
    }

    private func buildHeader() {
        let label = UILabel(); label.font = Fonts.mono(12); Fonts.tracked(label, "SEGUIR LEYENDO")
        continueTitle.font = Fonts.ui(22, weight: .semibold); continueTitle.numberOfLines = 2
        continueMeta.font = Fonts.mono(13)
        let button = UIButton(type: .system)
        button.setTitle("Continuar", for: .normal); button.titleLabel?.font = Fonts.ui(15, weight: .medium)
        button.layer.cornerRadius = 8; button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        button.addTarget(self, action: #selector(continueReading), for: .touchUpInside)
        button.tag = 99
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        let texts = UIStackView(arrangedSubviews: [continueTitle, continueMeta]); texts.axis = .vertical; texts.spacing = 6
        let row = UIStackView(arrangedSubviews: [texts, button]); row.axis = .horizontal; row.alignment = .bottom; row.spacing = 24
        continueBar.translatesAutoresizingMaskIntoConstraints = false
        continueBar.heightAnchor.constraint(equalToConstant: 2).isActive = true
        continueBar.layer.cornerRadius = 1; continueBar.clipsToBounds = true
        continueFill.frame = .zero
        continueBar.addSubview(continueFill)
        let stack = UIStackView(arrangedSubviews: [label, row, continueBar]); stack.axis = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let top = UIView(), bottom = UIView()
        for v in [top, bottom] { v.translatesAutoresizingMaskIntoConstraints = false; v.heightAnchor.constraint(equalToConstant: 1).isActive = true; header.addSubview(v) }
        top.tag = 1; bottom.tag = 2
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            top.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 32),
            top.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -32),
            bottom.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 22),
            bottom.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 32),
            bottom.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -32),
            bottom.bottomAnchor.constraint(equalTo: header.bottomAnchor)
        ])
    }

    private func updateContinue() {
        guard let id = Settings.shared.lastOpenedDocID, let doc = ContentStore.shared.doc(id: id) else {
            tableView.tableHeaderView = nil; continueDoc = nil; return
        }
        continueDoc = doc
        let p = ContentStore.shared.progress(for: doc.id)
        continueTitle.text = doc.title
        let left = Int(Double(doc.minutes ?? 0) * (1 - p))
        continueMeta.text = "\(Int(p * 100))% · quedan \(left) min"
        header.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 10)
        let size = header.systemLayoutSizeFitting(CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height))
        header.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: size.height)
        tableView.tableHeaderView = header
        header.layoutIfNeeded()
        continueFill.frame = CGRect(x: 0, y: 0, width: continueBar.bounds.width * CGFloat(p), height: 2)
    }

    @objc private func applyTheme() {
        let pal = self.pal
        view.backgroundColor = pal.bg; tableView.backgroundColor = pal.bg
        navigationController?.navigationBar.barTintColor = pal.bg
        navigationController?.navigationBar.tintColor = pal.text
        navigationController?.navigationBar.largeTitleTextAttributes = [.foregroundColor: pal.text, .font: Fonts.ui(34, weight: .bold)]
        navigationController?.navigationBar.titleTextAttributes = [.foregroundColor: pal.text, .font: Fonts.ui(17, weight: .semibold)]
        navigationController?.navigationBar.barStyle = .default
        search.searchBar.tintColor = pal.text
        continueTitle.textColor = pal.text; continueMeta.textColor = pal.secondary
        continueBar.backgroundColor = pal.hairline; continueFill.backgroundColor = pal.text
        for sub in header.subviews {
            if sub.tag == 1 || sub.tag == 2 { sub.backgroundColor = pal.hairline }
            if let s = sub as? UIStackView, let l = s.arrangedSubviews.first as? UILabel { l.textColor = pal.secondary }
        }
        if let b = header.viewWithTag(99) as? UIButton { b.backgroundColor = pal.text; b.setTitleColor(pal.bg, for: .normal) }
        footer.textColor = pal.secondary
        tableView.reloadData()
    }

    @objc private func reload() {
        all = ContentStore.shared.docs
        filter()
        let when: String
        if let d = Settings.shared.lastSync {
            let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"; f.locale = Locale(identifier: "es_AR")
            when = "sincronizado " + f.string(from: d)
        } else { when = "contenido del paquete" }
        footer.text = "    \(all.count) documentos · todo offline · \(when)"
        updateContinue()
    }

    private func filter() {
        let q = (search.searchBar.text ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        shown = q.isEmpty ? all : all.filter {
            ($0.title + " " + ($0.description ?? "")).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q)
        }
        tableView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) { filter() }

    @objc private func tapRefresh() { sync(silent: false) }

    // MARK: banner de progreso (debajo de la barra, no mueve la lista)
    // Muestra los tres pasos con una linea que se va llenando: revisar Google Docs,
    // publicar (el sitio convierte, ~1 min) y bajar al iPad.
    private let banner = UIView()
    private let bannerText = UILabel()
    private let bannerRight = UILabel()
    private let bannerFill = UIView()
    private let bannerTrack = UIView()
    private var bannerFillWidth: NSLayoutConstraint?
    private var bannerInstalled = false
    private var bannerHideWork: DispatchWorkItem?

    private func installBanner() {
        guard !bannerInstalled, let host = navigationController?.view, let bar = navigationController?.navigationBar else { return }
        bannerInstalled = true
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.isHidden = true; banner.alpha = 0
        bannerText.font = Fonts.ui(14, weight: .medium)
        bannerRight.font = Fonts.mono(12); bannerRight.textAlignment = .right
        bannerRight.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [bannerText, bannerRight]); row.axis = .horizontal; row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        bannerTrack.translatesAutoresizingMaskIntoConstraints = false
        bannerFill.translatesAutoresizingMaskIntoConstraints = false
        bannerTrack.addSubview(bannerFill)
        banner.addSubview(row); banner.addSubview(bannerTrack)
        host.addSubview(banner)
        let w = bannerFill.widthAnchor.constraint(equalTo: bannerTrack.widthAnchor, multiplier: 0.001)
        bannerFillWidth = w
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: bar.bottomAnchor),
            banner.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            row.topAnchor.constraint(equalTo: banner.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 32),
            row.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -32),
            bannerTrack.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 10),
            bannerTrack.leadingAnchor.constraint(equalTo: banner.leadingAnchor),
            bannerTrack.trailingAnchor.constraint(equalTo: banner.trailingAnchor),
            bannerTrack.heightAnchor.constraint(equalToConstant: 2),
            bannerTrack.bottomAnchor.constraint(equalTo: banner.bottomAnchor),
            bannerFill.leadingAnchor.constraint(equalTo: bannerTrack.leadingAnchor),
            bannerFill.topAnchor.constraint(equalTo: bannerTrack.topAnchor),
            bannerFill.bottomAnchor.constraint(equalTo: bannerTrack.bottomAnchor),
            w
        ])
    }

    /// `progress` 0...1 llena la linea. `done` lo deja un momento y lo esconde.
    private func showBanner(_ text: String, right: String = "", progress: Double, done: Bool = false) {
        installBanner()
        let pal = self.pal
        banner.backgroundColor = pal.bg
        bannerText.textColor = pal.text; bannerRight.textColor = pal.secondary
        bannerTrack.backgroundColor = pal.hairline; bannerFill.backgroundColor = pal.text
        bannerText.text = text; bannerRight.text = right
        bannerHideWork?.cancel()
        if banner.isHidden { banner.isHidden = false; navigationController?.view.layoutIfNeeded() }
        if let old = bannerFillWidth {
            old.isActive = false
            let w = bannerFill.widthAnchor.constraint(equalTo: bannerTrack.widthAnchor, multiplier: CGFloat(max(0.001, min(1, progress))))
            w.isActive = true; bannerFillWidth = w
        }
        UIView.animate(withDuration: 0.35) { self.banner.alpha = 1; self.navigationController?.view.layoutIfNeeded() }
        if done {
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                UIView.animate(withDuration: 0.4, animations: { self.banner.alpha = 0 }) { _ in self.banner.isHidden = true }
            }
            bannerHideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }
    }

    /// Un solo boton, manual (el usuario no quiere nada automatico): 1) el sitio compara Drive
    /// con lo publicado y, si hay cambios, convierte y publica (~1 min); 2) se espera; 3) se baja.
    private var syncing = false
    private func sync(silent: Bool) {
        guard !syncing else { return }
        syncing = true
        showBanner("Revisando Google Docs", right: "1/3", progress: 0.08)
        let done: (Result<Int, Error>) -> Void = { result in
            self.syncing = false
            self.reload()
            switch result {
            case .success(let n):
                self.showBanner(n == 0 ? "Todo al dia" : "Listo · \(n) documento(s) nuevos", right: "", progress: 1, done: true)
            case .failure(let e):
                self.showBanner(e.localizedDescription, right: "", progress: 1, done: true)
            }
        }
        let download = {
            self.showBanner("Bajando al iPad", right: "3/3", progress: 0.9)
            ContentStore.shared.refresh(completion: done)
        }
        ContentStore.shared.checkPublish { state in
            guard let state = state, !state.upToDate else { download(); return }
            if !state.building {
                // Drive tiene cambios pero no se pudo disparar (p. ej. fallo repetido): se baja lo que hay.
                self.showBanner(state.error ?? "No se pudo publicar", right: "", progress: 0.3)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: download)
                return
            }
            self.waitForPublish(started: Date(), attempts: 30) { published in
                if !published { self.showBanner("Sigue publicando; proba de nuevo en un minuto", right: "", progress: 0.85) }
                download()
            }
        }
    }

    /// Consulta cada 5 s hasta que el sitio diga que esta al dia (maximo `attempts` veces).
    /// La linea avanza con el tiempo (un build tarda ~1 min) entre 15% y 85%.
    private func waitForPublish(started: Date, attempts: Int, completion: @escaping (Bool) -> Void) {
        guard attempts > 0 else { completion(false); return }
        let secs = Int(Date().timeIntervalSince(started))
        showBanner("Publicando en el sitio (tarda un minuto)", right: "2/3 · \(secs) s", progress: 0.15 + 0.7 * min(1, Double(secs) / 60))
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            ContentStore.shared.checkPublish { state in
                if let s = state, s.upToDate { completion(true) }
                else if let s = state, !s.building { completion(false) }
                else { self.waitForPublish(started: started, attempts: attempts - 1, completion: completion) }
            }
        }
    }

    @objc private func openSettings() {
        let nav = UINavigationController(rootViewController: SettingsViewController())
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    @objc private func continueReading() {
        if let doc = continueDoc { open(doc) }
    }

    private func open(_ doc: Doc) {
        Settings.shared.lastOpenedDocID = doc.id
        navigationController?.pushViewController(ReaderViewController(doc: doc), animated: true)
    }

    // MARK: table
    override func numberOfSections(in tableView: UITableView) -> Int { return 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return shown.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "doc", for: indexPath) as! DocCell
        let d = shown[indexPath.row]
        cell.apply(pal)
        cell.titleLabel.text = d.title
        let p = ContentStore.shared.progress(for: d.id)
        let state = p >= 0.97 ? "leído" : (p > 0.01 ? "\(Int(p * 100))%" : "nuevo")
        cell.metaLabel.text = "\(shortDate(d.updated)) · \(d.minutes ?? 0) min · \(state)"
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        open(shown[indexPath.row])
    }

    private func shortDate(_ s: String?) -> String {
        // "11 de ago de 2026" -> "11 ago"
        guard let s = s else { return "" }
        let parts = s.replacingOccurrences(of: " de ", with: " ").split(separator: " ")
        return parts.count >= 2 ? "\(parts[0]) \(parts[1])" : s
    }
}

extension UIViewController {
    func toast(_ text: String) {
        let pal = Settings.shared.palette
        let l = UILabel()
        l.text = text; l.font = Fonts.ui(15, weight: .medium); l.textColor = pal.bg; l.backgroundColor = pal.text
        l.textAlignment = .center; l.layer.cornerRadius = 8; l.clipsToBounds = true; l.alpha = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            l.heightAnchor.constraint(equalToConstant: 40),
            l.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
        UIView.animate(withDuration: 0.2, animations: { l.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: { l.alpha = 0 }) { _ in l.removeFromSuperview() }
        }
    }
}
