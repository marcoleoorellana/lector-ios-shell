import UIKit

/// Depuración remota: si existe Documents/snap.on, guarda Documents/snap.png cada 2 s (se lee por SSH).
/// Se pausa en segundo plano: capturar ahí no sirve y gasta batería.
enum DebugSnap {
    private static var timer: Timer?
    private static weak var window: UIWindow?

    static func attach(window w: UIWindow) { window = w; start() }

    static func start() {
        guard timer == nil, DebugSnap.window != nil else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let marker = docs.appendingPathComponent("snap.on"), out = docs.appendingPathComponent("snap.png")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            guard let w = DebugSnap.window, FileManager.default.fileExists(atPath: marker.path) else { return }
            let r = UIGraphicsImageRenderer(bounds: w.bounds)
            let img = r.image { _ in w.drawHierarchy(in: w.bounds, afterScreenUpdates: false) }
            try? img.pngData()?.write(to: out)
        }
    }

    static func stop() { timer?.invalidate(); timer = nil }
}
