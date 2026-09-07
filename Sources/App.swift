import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var backgroundedAt: Date?
    private var locked = false

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        application.isIdleTimerDisabled = true // leer y predicar sin que la pantalla se apague
        let nav = UINavigationController(rootViewController: LibraryViewController())
        nav.navigationBar.isTranslucent = false
        nav.navigationBar.shadowImage = UIImage()
        nav.navigationBar.setBackgroundImage(UIImage(), for: .default)
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = nav
        w.makeKeyAndVisible()
        window = w
        lockIfNeeded()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) { backgroundedAt = Date() }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Re-pedir PIN si estuvo más de 10 minutos en segundo plano.
        if let t = backgroundedAt, Date().timeIntervalSince(t) > 600 { lockIfNeeded() }
    }

    private func lockIfNeeded() {
        guard Settings.shared.pinEnabled, !locked, let root = window?.rootViewController else { return }
        locked = true
        let pin = PinViewController(mode: .unlock) { [weak self] in self?.locked = false }
        (root.presentedViewController ?? root).present(pin, animated: false)
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
