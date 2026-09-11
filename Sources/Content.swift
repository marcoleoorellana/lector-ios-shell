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
    /// Hash del HTML convertido. Cambia también cuando cambia el conversor
    /// (aunque el doc no se edite), así la app re-baja el HTML regenerado.
    let hash: String?
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
        // Primero el sincronizado; si no existe o no es JSON valido (una version vieja guardaba
        // el index.html del sitio con ese nombre), el del paquete.
        for url in [syncDir.appendingPathComponent("styles.json"), bundleDir.appendingPathComponent("styles.json")] {
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]], !obj.isEmpty {
                styles = obj
                break
            }
        }
    }

    private func existing(_ url: URL) -> URL? { return fm.fileExists(atPath: url.path) ? url : nil }

    /// Un `path` de docs.json solo puede apuntar dentro de content/docs/ (el manifiesto puede venir de la red).
    private func safe(_ path: String) -> Bool {
        return path.hasPrefix("docs/") && !path.hasPrefix("/") && !path.contains("..")
    }

    func doc(id: String) -> Doc? { return docs.first { $0.id == id } }

    func html(for doc: Doc) -> String {
        guard safe(doc.path) else { return "<p>No se pudo abrir el documento.</p>" }
        let url = existing(syncDir.appendingPathComponent(doc.path)) ?? bundleDir.appendingPathComponent(doc.path)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "<p>No se pudo abrir el documento.</p>"
    }

    /// Base para recursos relativos (imágenes) del HTML.
    var baseURL: URL { return Bundle.main.resourceURL! }

    // MARK: progreso de lectura (0...1) por documento
    func progress(for id: String) -> Double { return UserDefaults.standard.double(forKey: "progress." + id) }
    func setProgress(_ p: Double, for id: String) { UserDefaults.standard.set(min(max(p, 0), 1), forKey: "progress." + id) }

    /// Estado de /api/auto-publish: el sitio compara Google Drive con lo publicado y,
    /// si hay cambios, dispara el build solo. `nil` si no se pudo consultar (sin internet,
    /// origen viejo sin ese endpoint): en ese caso se sigue con la descarga normal.
    struct PublishState { let upToDate: Bool; let building: Bool; let error: String? }

    func checkPublish(completion: @escaping (PublishState?) -> Void) {
        let base = Settings.shared.contentBaseURL
        guard let baseURL = URL(string: base), !base.isEmpty else { completion(nil); return }
        var req = URLRequest(url: baseURL.appendingPathComponent("api/auto-publish"))
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 25
        URLSession(configuration: .ephemeral).dataTask(with: req) { data, resp, _ in
            var state: PublishState? = nil
            if (resp as? HTTPURLResponse)?.statusCode == 200, let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], obj["ok"] as? Bool == true {
                state = PublishState(upToDate: obj["upToDate"] as? Bool ?? true,
                                     building: obj["building"] as? Bool ?? false,
                                     error: obj["error"] as? String)
            }
            DispatchQueue.main.async { completion(state) }
        }.resume()
    }

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
        session.dataTask(with: req) { data, resp, error in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let data = data, let remote = try? JSONDecoder().decode([Doc].self, from: data) else {
                let fallback = NSError(domain: "lector", code: 2, userInfo: [NSLocalizedDescriptionKey: code == 200 || code == 0 ? "docs.json inválido" : "docs.json: HTTP \(code)"])
                DispatchQueue.main.async { completion(.failure(error ?? fallback)) }
                return
            }
            // El manifiesto es remoto: ids repetidos no pueden reventar la app, y los path se validan antes de escribir.
            DispatchQueue.main.async {
                let known = Dictionary(self.docs.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                let changed = remote.filter { d in
                    guard self.safe(d.path) else { return false }
                    guard let k = known[d.id] else { return true }
                    // Con hash: se re-baja si cambió el HTML generado (edición del doc
                    // O cambio de código del conversor). Sin hash (manifiesto viejo),
                    // cae a la fecha del doc.
                    if let h = d.hash {
                        return k.hash != h || !self.fm.fileExists(atPath: self.syncDir.appendingPathComponent(d.path).path)
                    }
                    return k.modifiedTime != d.modifiedTime || !self.fm.fileExists(atPath: self.syncDir.appendingPathComponent(d.path).path)
                }
                let group = DispatchGroup()
                let counter = DispatchQueue(label: "lector.sync.counter")
                var failures = 0
                for d in changed {
                    group.enter()
                    session.dataTask(with: baseURL.appendingPathComponent(d.path)) { html, hResp, _ in
                        let ok = ((hResp as? HTTPURLResponse)?.statusCode ?? 0) == 200
                        if ok, let html = html {
                            let dest = self.syncDir.appendingPathComponent(d.path)
                            try? self.fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try? html.write(to: dest)
                        } else { counter.sync { failures += 1 } }
                        group.leave()
                    }.resume()
                }
                group.enter()
                session.dataTask(with: baseURL.appendingPathComponent("styles.json")) { s, sResp, _ in
                    // Solo si es JSON de verdad: Pages contesta index.html (200) a rutas inexistentes.
                    if ((sResp as? HTTPURLResponse)?.statusCode ?? 0) == 200, let s = s,
                       (try? JSONSerialization.jsonObject(with: s)) as? [String: Any] != nil {
                        try? s.write(to: self.syncDir.appendingPathComponent("styles.json"))
                    }
                    group.leave()
                }.resume()
                group.notify(queue: .main) {
                    let failed = counter.sync { failures }
                    if failed == 0 {
                        try? data.write(to: self.syncDir.appendingPathComponent("docs.json"))
                        Settings.shared.lastSync = Date()
                        self.load()
                        NotificationCenter.default.post(name: .contentChanged, object: nil)
                        completion(.success(changed.count))
                    } else {
                        completion(.failure(NSError(domain: "lector", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(failed) documento(s) no se pudieron bajar"])))
                    }
                }
            }
        }.resume()
    }
}
