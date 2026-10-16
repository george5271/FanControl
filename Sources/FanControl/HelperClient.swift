import Foundation
import FanControlShared

/// XPC client for the root helper `fancontrold`.
/// Keeps one connection open for the app's lifetime: the helper hands the fans back
/// to macOS as soon as that connection drops (app quit or crash).
final class HelperClient {
    enum State: Equatable {
        case unknown
        case connected
        case notInstalled
        case outdated(String)
        case failed(String)
    }

    private var connection: NSXPCConnection?
    private var versionChecked = false

    func apply(_ targets: [Double], completion: @escaping (State) -> Void) {
        if !versionChecked {
            checkVersion { [weak self] state in
                guard state == .connected else { return completion(state) }
                self?.versionChecked = true
                self?.sendApply(targets, completion: completion)
            }
        } else {
            sendApply(targets, completion: completion)
        }
    }

    /// Synchronous so it completes before the process exits.
    func resetToAutoSync() {
        guard let connection else { return }
        let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { _ in } as? FanHelperProtocol
        proxy?.resetToAuto { _ in }
        connection.invalidate()
    }

    // MARK: - Private

    private func sendApply(_ targets: [Double], completion: @escaping (State) -> Void) {
        let proxy = remote { completion($0) }
        proxy?.apply(targets: targets.map { NSNumber(value: $0) }) { error in
            DispatchQueue.main.async { completion(error.map { .failed($0) } ?? .connected) }
        }
    }

    private func checkVersion(completion: @escaping (State) -> Void) {
        let proxy = remote { completion($0) }
        proxy?.version { version in
            DispatchQueue.main.async {
                completion(version == HelperConstants.version ? .connected : .outdated(version))
            }
        }
    }

    private func remote(onError: @escaping (State) -> Void) -> FanHelperProtocol? {
        let connection = currentConnection()
        return connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async {
                self?.dropConnection()
                let code = (error as NSError).code
                // 4099 (connection invalid): the Mach service is not registered, i.e. helper not installed,
                // or the helper rejected us (code signature mismatch).
                onError(code == NSXPCConnectionInvalid ? .notInstalled : .failed(error.localizedDescription))
            }
        } as? FanHelperProtocol
    }

    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }
        let c = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        c.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.dropConnection() }
        }
        c.resume()
        connection = c
        return c
    }

    private func dropConnection() {
        connection?.invalidationHandler = nil
        connection?.invalidate()
        connection = nil
        versionChecked = false
    }
}
