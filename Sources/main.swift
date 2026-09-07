import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var backgroundedAt: Date?
    private var locked = false
    private var cover: UIView?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        application.isIdleTimerDisabled = true // leer y predicar sin que la pantalla se apague
        let nav = UINavigationController(rootViewController: LibraryViewController())
        nav.navigationBar.isTranslucent = false
        nav.navigationBar.shadowImage = UIImage()
        nav.view.backgroundColor = Settings.shared.palette.bg
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = Settings.shared.palette.bg
        w.rootViewController = nav
        DebugSnap.attach(window: w)
        w.makeKeyAndVisible()
        window = w
        lockIfNeeded()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        backgroundedAt = Date()
        DebugSnap.stop()
        showCover() // el snapshot del app switcher se toma después de esto: que no muestre el sermón
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Re-pedir PIN si estuvo más de 10 minutos en segundo plano.
        if let t = backgroundedAt, Date().timeIntervalSince(t) > 600 { lockIfNeeded() }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        cover?.removeFromSuperview(); cover = nil
        DebugSnap.start()
    }

    private func showCover() {
        guard cover == nil, let w = window else { return }
        let v = UIView(frame: w.bounds)
        v.backgroundColor = Settings.shared.palette.bg
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        w.addSubview(v)
        cover = v
    }

    private func lockIfNeeded() {
        guard Settings.shared.pinEnabled, let root = window?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        guard !locked, !(top is PinViewController) else { return }
        locked = true
        let pin = PinViewController(mode: .unlock) { [weak self] in self?.locked = false }
        top.present(pin, animated: false)
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
