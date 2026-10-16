import Foundation

/// Fan description read from the SMC.
public struct FanInfo: Identifiable, Equatable {
    public let id: Int
    public var minRPM: Double
    public var maxRPM: Double
    public var actualRPM: Double
    public var targetRPM: Double
    public var isManual: Bool
}

public extension SMC {
    var fanCount: Int {
        Int(readDouble("FNum") ?? 0)
    }

    func fan(_ i: Int) -> FanInfo? {
        guard let maxRPM = readDouble("F\(i)Mx") else { return nil }
        return FanInfo(id: i,
                       minRPM: readDouble("F\(i)Mn") ?? 0,
                       maxRPM: maxRPM,
                       actualRPM: readDouble("F\(i)Ac") ?? 0,
                       targetRPM: readDouble("F\(i)Tg") ?? 0,
                       isManual: (readDouble("F\(i)Md") ?? 0) == 1)
    }

    func fans() -> [FanInfo] {
        (0..<fanCount).compactMap { fan($0) }
    }

    /// SMC keys of CPU core temperature sensors.
    /// Apple Silicon: Tp* (performance cores) and Te* (efficiency cores).
    /// Intel: TC0P/TC0D/TC0E/TC0F and per-core TC1C, TC2C...
    func cpuTemperatureKeys() -> [String] {
        let intel: Set<String> = ["TC0P", "TC0D", "TC0E", "TC0F", "TC0H"]
        return allKeys().filter { key in
            let isAppleSilicon = key.hasPrefix("Tp") || key.hasPrefix("Te")
            let isIntelCore = key.hasPrefix("TC") && key.hasSuffix("C")
            guard isAppleSilicon || isIntelCore || intel.contains(key) else { return false }
            // Only keep sensors that currently report a plausible temperature.
            guard let t = readDouble(key) else { return false }
            return t > 5 && t < 130
        }
    }

    /// Hottest of the given sensors, ignoring implausible readings.
    func maxTemperature(of keys: [String]) -> Double? {
        keys.compactMap { readDouble($0) }.filter { $0 > 5 && $0 < 130 }.max()
    }
}
