import SwiftUI

@main
struct FanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Debug builds only: `FanControl --snapshot out.png` renders the menu to an image and exits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            snapshotMenu(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }

    private var window: NSWindow?

    /// Opening the app again (Finder, Launchpad, Spotlight) shows the controls in a regular window,
    /// for when the menu bar icon is hidden behind the notch or the menu bar is full.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "FanControl"
            // The panel draws its own dark background: blend the title bar into it.
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = Theme.nsInk
            w.contentView = NSHostingView(rootView: MenuView().environmentObject(AppModel.shared))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return false
    }

    #if DEBUG
    private func snapshotMenu(to url: URL) {
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))  // let the helper answer
        let host = NSHostingView(rootView: MenuView().environmentObject(AppModel.shared))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif
}
