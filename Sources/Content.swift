import Foundation

struct Doc: Codable {
    let id: String
    let slug: String
    let title: String
    let path: String
    let description: String?
    let updated: String?
    let modifiedTime: String?
    let minutes: Int?
}

/// Contenido: docs.json + docs/*.html + styles.json.
/// Prioridad: copia sincronizada en Application Support; si no hay, la del bundle (content/).
final class ContentStore {
    static let shared = ContentStore()
    private(set) var docs: [Doc] = []
    private(set) var styles: [String: [String: Any]] = [:]
    private let fm = FileManager.default

    private var bundleDir: URL { return Bundle.main.resourceURL!.appendingPathComponent("content", isDirectory: true) }
    private var syncDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("content", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private init() { load() }

    func load() {
        let manifest = existing(syncDir.appendingPathComponent("docs.json")) ?? bundleDir.appendingPathComponent("docs.json")
        if let data = try? Data(contentsOf: manifest), let list = try? JSONDecoder().decode([Doc].self, from: data) {
            docs = list
        }
        let stylesURL = existing(syncDir.appendingPathComponent("styles.json")) ?? bundleDir.appendingPathComponent("styles.json")
        if let data = try? Data(contentsOf: stylesURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            styles = obj
        }
    }

    private func existing(_ url: URL) -> URL? { return fm.fileExists(atPath: url.path) ? url : nil }

    func doc(id: String) -> Doc? { return docs.first { $0.id == id } }

    func html(for doc: Doc) -> String {
        let url = existing(syncDir.appendingPathComponent(doc.path)) ?? bundleDir.appendingPathComponent(doc.path)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "<p>No se pudo abrir el documento.</p>"
    }

    /// Base para recursos relativos (imágenes) del HTML.
    var baseURL: URL { return Bundle.main.resourceURL! }

    // MARK: progreso de lectura (0...1) por documento
    func progress(for id: String) -> Double { return UserDefaults.standard.double(forKey: "progress." + id) }
    func setProgress(_ p: Double, for id: String) { UserDefaults.standard.set(min(max(p, 0), 1), forKey: "progress." + id) }

    // MARK: sincronización remota (opcional): baja docs.json y los HTML que cambiaron
    func refresh(completion: @escaping (Result<Int, Error>) -> Void) {
        let base = Settings.shared.contentBaseURL
        guard let baseURL = URL(string: base), !base.isEmpty else {
            completion(.failure(NSError(domain: "lector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Configurá el origen en Ajustes."])))
            return
        }
        let session = URLSession(configuration: .ephemeral)
        var req = URLRequest(url: baseURL.appendingPathComponent("docs.json"))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        session.dataTask(with: req) { data, _, error in
            guard let data = data, let remote = try? JSONDecoder().decode([Doc].self, from: data) else {
                DispatchQueue.main.async { completion(.failure(error ?? NSError(domain: "lector", code: 2, userInfo: [NSLocalizedDescriptionKey: "docs.json inválido"]))) }
                return
            }
            let known = Dictionary(uniqueKeysWithValues: self.docs.map { ($0.id, $0) })
            let changed = remote.filter { d in
                guard let k = known[d.id] else { return true }
                return k.modifiedTime != d.modifiedTime || !self.fm.fileExists(atPath: self.syncDir.appendingPathComponent(d.path).path)
            }
            let group = DispatchGroup()
            var failures = 0
            for d in changed {
                group.enter()
                session.dataTask(with: baseURL.appendingPathComponent(d.path)) { html, _, _ in
                    if let html = html {
                        let dest = self.syncDir.appendingPathComponent(d.path)
                        try? self.fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? html.write(to: dest)
                    } else { failures += 1 }
                    group.leave()
                }.resume()
            }
            group.enter()
            session.dataTask(with: baseURL.appendingPathComponent("styles.json")) { s, _, _ in
                if let s = s { try? s.write(to: self.syncDir.appendingPathComponent("styles.json")) }
                group.leave()
            }.resume()
            group.notify(queue: .main) {
                if failures == 0 {
                    try? data.write(to: self.syncDir.appendingPathComponent("docs.json"))
                    Settings.shared.lastSync = Date()
                    self.load()
                    NotificationCenter.default.post(name: .contentChanged, object: nil)
                    completion(.success(changed.count))
                } else {
                    completion(.failure(NSError(domain: "lector", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(failures) documento(s) no se pudieron bajar"])))
                }
            }
        }.resume()
    }
}
