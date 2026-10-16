// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v13)],
    targets: [
        // SMC access (reading sensors/fans, writing fan mode and target speed).
        .target(name: "SMCKit", linkerSettings: [.linkedFramework("IOKit")]),
        // XPC protocol shared by the app and the helper.
        .target(name: "FanControlShared"),
        // Root LaunchDaemon that performs SMC writes.
        .executableTarget(name: "fancontrold", dependencies: ["SMCKit", "FanControlShared"]),
        // Menu bar app.
        .executableTarget(name: "FanControl", dependencies: ["SMCKit", "FanControlShared"]),
    ]
)
