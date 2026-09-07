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
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Ajustes", style: .plain, target: self, action: #selector(openSettings)),
            UIBarButtonItem(title: "Claude", style: .plain, target: self, action: #selector(openClaude))
        ]

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
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(pullRefresh), for: .valueChanged)

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
        if let id = try? String(contentsOf: docs.appendingPathComponent("snap.open"), encoding: .utf8),
           let doc = ContentStore.shared.doc(id: id.trimmingCharacters(in: .whitespacesAndNewlines)) {
            debugOpened = true
            let r = ReaderViewController(doc: doc)
            r.debugPreach = FileManager.default.fileExists(atPath: docs.appendingPathComponent("snap.preach").path)
            navigationController?.pushViewController(r, animated: true)
        }
    }

    private func buildHeader() {
        let label = UILabel(); label.text = "SEGUIR LEYENDO"; label.font = Fonts.mono(12)
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
        navigationController?.navigationBar.barStyle = Settings.shared.theme == .dark ? .black : .default
        search.searchBar.tintColor = pal.text
        continueTitle.textColor = pal.text; continueMeta.textColor = pal.secondary
        continueBar.backgroundColor = pal.hairline; continueFill.backgroundColor = pal.text
        for sub in header.subviews {
            if sub.tag == 1 || sub.tag == 2 { sub.backgroundColor = pal.hairline }
            if let s = sub as? UIStackView, let l = s.arrangedSubviews.first as? UILabel { l.textColor = pal.secondary }
        }
        if let b = header.viewWithTag(99) as? UIButton { b.backgroundColor = pal.text; b.setTitleColor(pal.bg, for: .normal) }
        footer.textColor = pal.secondary
        refreshControl?.tintColor = pal.secondary
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

    @objc private func pullRefresh() {
        ContentStore.shared.refresh { result in
            self.refreshControl?.endRefreshing()
            switch result {
            case .success(let n): self.toast(n == 0 ? "Sin cambios" : "\(n) documento(s) actualizados")
            case .failure(let e): self.toast(e.localizedDescription)
            }
        }
    }

    @objc private func openSettings() {
        let nav = UINavigationController(rootViewController: SettingsViewController())
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    @objc private func openClaude() {
        navigationController?.pushViewController(ClaudeViewController(), animated: true)
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
