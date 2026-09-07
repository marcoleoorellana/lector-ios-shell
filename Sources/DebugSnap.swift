import UIKit

/// Depuración remota: si existe Documents/snap.on, guarda Documents/snap.png cada 2 s (se lee por SSH).
enum DebugSnap {
    private static var timer: Timer?
    static func start(window: UIWindow) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let marker = docs.appendingPathComponent("snap.on"), out = docs.appendingPathComponent("snap.png")
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            guard FileManager.default.fileExists(atPath: marker.path) else { return }
            let r = UIGraphicsImageRenderer(bounds: window.bounds)
            let img = r.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
            try? img.pngData()?.write(to: out)
        }
    }
}
