import SwiftUI

@main
struct FanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        // The menu bar item and its panel are AppKit (StatusPanel.swift); SwiftUI needs a scene anyway.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Debug builds only: `FanControl --snapshot out.png` renders the menu to an image and exits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            snapshotMenu(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        #endif
        statusBar = StatusBarController(model: AppModel.shared)
        #if DEBUG
        // `FanControl --open-panel`: open the panel at launch (the item may sit behind the notch).
        if args.contains("--open-panel") || args.contains("--anim-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.statusBar?.show() }
        }
        // `FanControl --anim-test`: open and close the settings card, log the panel height over time.
        if args.contains("--anim-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.statusBar?.runAnimationTest() }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }

    /// Opening the app again (Finder, Launchpad, Spotlight) drops the menu panel down, at the right
    /// edge of the screen when the item is hidden behind the notch or the menu bar is full.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar?.show()
        return false
    }

    #if DEBUG
    private func snapshotMenu(to url: URL) {
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))  // let the helper answer
        // Optional: --theme <system|ocean|violet|light> [--dark] [--settings] [--info] [--steps] [--chrome]
        let args = CommandLine.arguments
        var overrides = PanelOverrides()
        if let i = args.firstIndex(of: "--theme"), i + 1 < args.count {
            overrides.theme = ThemeChoice(rawValue: args[i + 1])
        }
        overrides.settingsOpen = args.contains("--settings")
        overrides.stepsOpen = args.contains("--steps")
        overrides.infoOpen = args.contains("--info")
        let host = NSHostingView(rootView: MenuView().environmentObject(AppModel.shared)
            .environment(\.panelOverrides, overrides)
            .environment(\.panelChrome, args.contains("--chrome") ? PanelChrome() : nil))
        host.appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))  // let the panel fit its window
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif
}
