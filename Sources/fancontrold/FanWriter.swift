import Foundation
import SMCKit
import FanControlShared

/// Performs all SMC writes. Every method must be called on `queue`.
final class FanWriter {
    let queue = DispatchQueue(label: "fancontrold.smc")

    /// If the app sends nothing for this long while fans are manual, control goes back to macOS.
    private let heartbeatTimeout: TimeInterval = 12

    private let smc: SMC
    private var lastApply = Date.distantPast
    private var anyManual = false
    private var usedFtst = false
    private var watchdog: DispatchSourceTimer?

    init() throws {
        smc = try SMC()
    }

    func start() {
        queue.sync { _ = resetToAuto() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self, self.anyManual else { return }
            if Date().timeIntervalSince(self.lastApply) > self.heartbeatTimeout {
                log("no heartbeat from app for \(Int(self.heartbeatTimeout))s, restoring automatic control")
                _ = self.resetToAuto()
            }
        }
        timer.resume()
        watchdog = timer
    }

    func apply(_ targets: [Double]) -> String? {
        lastApply = Date()
        let count = smc.fanCount
        var errors: [String] = []
        for i in 0..<min(count, targets.count) {
            do {
                if targets[i] < 0 {
                    try setManual(i, false)
                } else {
                    try setManual(i, true)
                    try smc.write("F\(i)Tg", value: clampedTarget(i, targets[i]))
                }
            } catch {
                errors.append("fan \(i): \(error)")
            }
        }
        anyManual = (0..<count).contains { smc.readDouble("F\($0)Md") == 1 }
        if !anyManual { releaseFtst() }
        if !errors.isEmpty { log(errors.joined(separator: "; ")) }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func resetToAuto() -> String? {
        var errors: [String] = []
        for i in 0..<smc.fanCount {
            do { try setManual(i, false) } catch { errors.append("fan \(i): \(error)") }
        }
        releaseFtst()
        anyManual = false
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    // MARK: - Private

    /// 0 means "stopped"; any other value is kept within the fan's supported range.
    private func clampedTarget(_ i: Int, _ rpm: Double) -> Double {
        guard rpm > 0 else { return 0 }
        let lo = smc.readDouble("F\(i)Mn") ?? 0
        let hi = smc.readDouble("F\(i)Mx") ?? rpm
        return min(max(rpm, lo), hi)
    }

    private func setManual(_ i: Int, _ manual: Bool) throws {
        let key = "F\(i)Md"
        let wanted: Double = manual ? 1 : 0
        if smc.readDouble(key) == wanted { return }
        var writeError: Error?
        do { try smc.write(key, value: wanted) } catch { writeError = error }
        // The SMC applies a mode change with a short delay, so poll the readback for up to a second.
        if writeError == nil {
            for _ in 0..<10 {
                if smc.readDouble(key) == wanted { return }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        if smc.readDouble(key) == wanted { return }
        guard manual, smc.hasKey("Ftst") else { throw writeError ?? SMC.SMCError.badData(key) }
        // Newer Apple Silicon Macs only accept manual mode after the "force test" flag is set,
        // and thermalmonitord takes a moment to let go of the fans.
        try smc.write("Ftst", value: 1)
        usedFtst = true
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.25)
            if (try? smc.write(key, value: 1)) != nil, smc.readDouble(key) == 1 { return }
        }
        throw SMC.SMCError.badData(key)
    }

    private func releaseFtst() {
        guard usedFtst || smc.readDouble("Ftst") == 1 else { return }
        try? smc.write("Ftst", value: 0)
        usedFtst = false
    }
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("\(stamp) fancontrold: \(message)\n".utf8))
}
