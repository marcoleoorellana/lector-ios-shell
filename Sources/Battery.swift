import UIKit

/// Lectura exacta de batería vía IORegistry (funciona en iPad con jailbreak; sin él cae a UIDevice, 1%).
enum Battery {
    struct Info {
        /// nil cuando el sistema todavía no reportó nivel (batteryLevel == -1).
        var percent: Int?
        var charging: Bool
        var externalPower: Bool
        var currentMAh: Int?
        var maxMAh: Int?
        var designMAh: Int?
        var cycles: Int?
        var voltageMV: Int?
        var amperageMA: Int?
        var temperatureC: Double?

        var healthPercent: Int? {
            guard let m = maxMAh, let d = designMAh, d > 0 else { return nil }
            return Int((Double(m) / Double(d) * 100).rounded())
        }
    }

    static func read() -> Info {
        UIDevice.current.isBatteryMonitoringEnabled = true
        // La primera lectura tras habilitar el monitoreo suele ser -1: sin dato, no 0 %.
        let level = UIDevice.current.batteryLevel
        var info = Info(percent: level < 0 ? nil : Int((level * 100).rounded()),
                        charging: UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full,
                        externalPower: UIDevice.current.batteryState != .unplugged)
        guard let props = registryProps() else { return info }
        func int(_ k: String) -> Int? { return (props[k] as? NSNumber)?.intValue }
        if let raw = int("AppleRawCurrentCapacity") { info.currentMAh = raw }
        if let max = int("AppleRawMaxCapacity") ?? int("MaxCapacity"), max > 200 { info.maxMAh = max }
        if let d = int("DesignCapacity") { info.designMAh = d }
        if let c = int("CycleCount") { info.cycles = c }
        if let v = int("Voltage") { info.voltageMV = v }
        if let a = int("InstantAmperage") ?? int("Amperage") { info.amperageMA = a }
        if let t = int("Temperature") { info.temperatureC = Double(t) / 100 }
        if let ext = props["ExternalConnected"] as? Bool { info.externalPower = ext }
        if let ch = props["IsCharging"] as? Bool { info.charging = ch }
        if let cur = info.currentMAh, let max = info.maxMAh, max > 0 {
            info.percent = Int((Double(cur) / Double(max) * 100).rounded())
        }
        return info
    }

    // IOKit por símbolos: el SDK de iOS no trae headers públicos, pero el framework está.
    private typealias io_object_t = UInt32
    @_silgen_name("IOServiceMatching") private static func IOServiceMatching(_ name: UnsafePointer<CChar>) -> Unmanaged<CFMutableDictionary>?
    @_silgen_name("IOServiceGetMatchingService") private static func IOServiceGetMatchingService(_ master: UInt32, _ matching: CFDictionary?) -> io_object_t
    @_silgen_name("IORegistryEntryCreateCFProperties") private static func IORegistryEntryCreateCFProperties(_ entry: io_object_t, _ props: UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, _ allocator: CFAllocator?, _ options: UInt32) -> Int32
    @_silgen_name("IOObjectRelease") private static func IOObjectRelease(_ obj: io_object_t) -> Int32

    private static func registryProps() -> [String: Any]? {
        for name in ["AppleSmartBattery", "AppleARMPMUCharger", "IOPMPowerSource"] {
            guard let matching = IOServiceMatching(name) else { continue }
            // IOServiceMatching devuelve +1 y IOServiceGetMatchingService la consume: no liberar de nuestro lado.
            let service = IOServiceGetMatchingService(0, matching.takeUnretainedValue())
            if service == 0 { continue }
            var props: Unmanaged<CFMutableDictionary>?
            let kr = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
            _ = IOObjectRelease(service)
            if kr == 0, let dict = props?.takeRetainedValue() as? [String: Any], !dict.isEmpty { return dict }
        }
        return nil
    }

    static func summary() -> String {
        let b = read()
        var parts: [String] = [b.percent.map { "\($0)%" } ?? "—"]
        if let c = b.currentMAh, let m = b.maxMAh { parts.append("\(c)/\(m) mAh") }
        parts.append(b.charging ? "cargando" : (b.externalPower ? "enchufado, sin cargar" : "batería"))
        if let a = b.amperageMA { parts.append("\(a) mA") }
        if let h = b.healthPercent, let cy = b.cycles { parts.append("salud \(h)% · \(cy) ciclos") }
        if let t = b.temperatureC { parts.append(String(format: "%.1f °C", t)) }
        return parts.joined(separator: " · ")
    }
}
