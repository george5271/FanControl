import Foundation
import FanControlShared

/// Launch at login via a per-user LaunchAgent. Works with ad-hoc signed apps,
/// unlike SMAppService which expects a stable Team ID.
enum LoginItem {
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(HelperConstants.appBundleID).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        let fm = FileManager.default
        guard enabled else {
            if isEnabled { try fm.removeItem(at: plistURL) }
            return
        }
        let plist: [String: Any] = [
            "Label": HelperConstants.appBundleID,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]
        try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    }
}
