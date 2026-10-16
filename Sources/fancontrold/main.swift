import Foundation
import FanControlShared

/// Privileged helper: a LaunchDaemon running as root that accepts fan commands over XPC.
/// It only exposes fan mode / target speed, never arbitrary SMC writes.

final class HelperService: NSObject, FanHelperProtocol {
    let writer: FanWriter
    init(writer: FanWriter) { self.writer = writer }

    func version(reply: @escaping (String) -> Void) {
        reply(HelperConstants.version)
    }

    func apply(targets: [NSNumber], reply: @escaping (String?) -> Void) {
        let values = targets.map { $0.doubleValue }
        writer.queue.async { reply(self.writer.apply(values)) }
    }

    func resetToAuto(reply: @escaping (String?) -> Void) {
        writer.queue.async { reply(self.writer.resetToAuto()) }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let writer: FanWriter
    private var connections = 0

    init(writer: FanWriter) { self.writer = writer }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Only the FanControl app (by its code signing identifier) may talk to the helper.
        connection.setCodeSigningRequirement("identifier \"\(HelperConstants.appBundleID)\"")
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = HelperService(writer: writer)
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.writer.queue.async {
                self.connections -= 1
                // The app quit or crashed: hand the fans back to macOS right away.
                if self.connections <= 0 {
                    self.connections = 0
                    log("app disconnected, restoring automatic control")
                    _ = self.writer.resetToAuto()
                }
            }
        }
        writer.queue.async { self.connections += 1 }
        connection.resume()
        return true
    }
}

let writer: FanWriter
do {
    writer = try FanWriter()
} catch {
    log("cannot open SMC: \(error)")
    exit(1)
}
writer.start()

// launchd stops us with SIGTERM (uninstall, shutdown): leave the fans in automatic mode.
signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: writer.queue)
sigterm.setEventHandler {
    _ = writer.resetToAuto()
    log("SIGTERM, fans returned to automatic control")
    exit(0)
}
sigterm.resume()

let delegate = ListenerDelegate(writer: writer)
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
log("started, version \(HelperConstants.version)")
RunLoop.main.run()
