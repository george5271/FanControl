import Foundation

/// Identifiers shared between the menu bar app and the privileged helper.
public enum HelperConstants {
    public static let machServiceName = "com.george527.fancontrol.helper"
    public static let appBundleID = "com.george527.fancontrol"
    /// Bump when the XPC protocol or helper behaviour changes, so the app can ask to reinstall.
    public static let version = "1.0"
    /// Target value meaning "give this fan back to macOS".
    public static let automatic: Double = -1
}

/// XPC interface of `fancontrold` (runs as root, writes to the SMC).
@objc(FanHelperProtocol)
public protocol FanHelperProtocol {
    func version(reply: @escaping (String) -> Void)

    /// One value per fan index: `HelperConstants.automatic` (< 0) returns the fan to macOS,
    /// 0 stops it, anything else is a target speed in RPM (clamped to the fan's min...max).
    /// Doubles as a heartbeat: if the app stops calling it, the helper restores automatic control.
    func apply(targets: [NSNumber], reply: @escaping (String?) -> Void)

    /// Returns every fan to automatic (macOS) control.
    func resetToAuto(reply: @escaping (String?) -> Void)
}
