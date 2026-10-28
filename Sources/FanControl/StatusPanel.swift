import AppKit
import Combine
import SwiftUI

// SwiftUI's MenuBarExtra(.window) does not animate its window when the content changes size: it
// snaps, or does not resize at all. So the item and its panel are our own (an NSStatusItem and a
// borderless NSPanel), and the panel window does not change size while it is open: animating a
// window frame, or even resizing it instantly downward, makes the window server briefly show the
// panel shifted down. The window is transparent and reaches the bottom of the screen; the visible
// panel (slab, rounded corners, shadow) is drawn by SwiftUI, which animates its height in the same
// render pass as the content.

/// Rounded corners, edge and shadow the borderless panel draws around the content.
struct PanelChrome {
    var cornerRadius: CGFloat = 16
    /// Transparent room around the panel for its shadow.
    var margins = EdgeInsets(top: 8, leading: 22, bottom: 34, trailing: 22)
}

private struct PanelChromeKey: EnvironmentKey {
    static let defaultValue: PanelChrome? = nil
}

extension EnvironmentValues {
    /// nil in debug snapshots, which render the content edge to edge.
    var panelChrome: PanelChrome? {
        get { self[PanelChromeKey.self] }
        set { self[PanelChromeKey.self] = newValue }
    }
}

/// Lets the panel content report its ideal size to the window hosting it.
private struct PanelSizeKey: EnvironmentKey {
    static let defaultValue: ((CGSize) -> Void)? = nil
}

extension EnvironmentValues {
    var panelSizeDidChange: ((CGSize) -> Void)? {
        get { self[PanelSizeKey.self] }
        set { self[PanelSizeKey.self] = newValue }
    }
}

/// Window content: hosts the SwiftUI panel and passes on its size and mouse moves.
final class PanelContainer: NSView {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    /// Last size the content asked for (including the chrome margins).
    private(set) var contentSize: CGSize = .zero
    var onContentSize: ((CGSize) -> Void)?
    var onMouseMoved: (() -> Void)?

    init<Content: View>(_ content: Content, chrome: PanelChrome) {
        super.init(frame: NSRect(x: 0, y: 0, width: 372, height: 520))
        // Mouse moves reach the view even while the app is not active.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        // The panel sizes its window itself; the hosting view just fills it.
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = bounds
        addSubview(host)
        host.rootView = AnyView(
            content
                .environment(\.panelChrome, chrome)
                .environment(\.panelSizeDidChange) { [weak self] size in
                    self?.contentSize = size
                    self?.onContentSize?(size)
                }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
    }
}

/// Drop-down panel under the status item.
///
/// While open the window keeps one frame, reaching from under the menu bar to the bottom of the
/// screen: resizing a window that grows downward briefly shows its old content shifted down before
/// the new content is drawn. Everything outside the visible slab is transparent, and the window
/// lets mouse events through to the apps below whenever the pointer is outside the slab.
final class MenuPanel: NSPanel {
    let host: PanelContainer
    var onClose: (() -> Void)?
    static let chrome = PanelChrome()

    init<Content: View>(content: Content) {
        host = PanelContainer(content, chrome: Self.chrome)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 372, height: 520),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // SwiftUI draws the shadow; a window shadow would outline the transparent margins
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovable = false
        contentView = host
        host.onContentSize = { [weak self] _ in self?.updateMousePassThrough() }
        host.onMouseMoved = { [weak self] in self?.updateMousePassThrough() }
    }

    override var canBecomeKey: Bool { true }

    /// Places the panel under `anchor` (the status item) and makes it reach the bottom of the screen.
    func place(under anchor: NSRect, on screen: NSScreen?) {
        let m = Self.chrome.margins
        let width = 372 + m.leading + m.trailing
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let top = anchor.minY - 6 + m.top
        var x = anchor.midX - width / 2
        x = min(max(x, visible.minX + 8 - m.leading), visible.maxX - width + m.trailing - 8)
        setFrame(NSRect(x: x, y: visible.minY, width: width, height: top - visible.minY), display: true)
    }

    /// Screen rectangle of the visible slab.
    private var slabFrame: NSRect {
        let m = Self.chrome.margins
        let height = max(0, host.contentSize.height - m.top - m.bottom)
        return NSRect(x: frame.minX + m.leading, y: frame.maxY - m.top - height,
                      width: frame.width - m.leading - m.trailing, height: height)
    }

    /// Takes the mouse only over the slab; elsewhere clicks and scrolls go to the windows below.
    func updateMousePassThrough() {
        let inside = slabFrame.contains(NSEvent.mouseLocation)
        if ignoresMouseEvents == inside { ignoresMouseEvents = !inside }
    }

    /// Esc closes the panel, like a menu.
    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func resignKey() {
        super.resignKey()
        onClose?()
    }
}

/// The menu bar item: its icon reflects the fans, a click opens the panel.
@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: MenuPanel
    private var observation: AnyCancellable?
    private var clickMonitor: Any?
    private var moveMonitor: Any?
    /// When the panel last closed: a click on the item that closed it must not reopen it.
    private var closedAt = Date.distantPast

    init(model: AppModel) {
        panel = MenuPanel(content: MenuView().environmentObject(model))
        super.init()
        panel.onClose = { [weak self] in self?.close() }
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        update(model)
        // objectWillChange fires before the change lands; read the model on the next turn of the run loop.
        observation = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update(model) }
    }

    // MARK: - Icon

    private func update(_ model: AppModel) {
        guard let button = item.button else { return }
        let state = MenuBarState(model)
        if button.toolTip != state.description {
            let image = NSImage(systemSymbolName: state.symbol, accessibilityDescription: state.description)
            image?.isTemplate = true
            button.image = image
            button.toolTip = state.description
        }
        let title = model.settings.showInMenuBar && !model.menuBarTitle.isEmpty ? " " + model.menuBarTitle : ""
        if button.title != title { button.title = title }
    }

    // MARK: - Panel

    @objc private func toggle() {
        if panel.isVisible {
            close()
        } else if Date().timeIntervalSince(closedAt) > 0.3 {
            show()
        }
    }

    func show() {
        // Lay the content out first so its size is known when the panel is placed.
        panel.host.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in self?.present() }
    }

    private func present() {
        guard let button = item.button else { return }
        let screen = button.window?.screen ?? NSScreen.main
        // An item hidden behind the notch has no usable position: open at the right edge instead.
        let anchor: NSRect
        if let buttonWindow = button.window, buttonWindow.isVisible, buttonWindow.screen != nil {
            anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        } else {
            let visible = screen?.visibleFrame ?? .zero
            anchor = NSRect(x: visible.maxX - 200, y: visible.maxY + 6, width: 0, height: 0)
        }
        panel.place(under: anchor, on: screen)
        panel.updateMousePassThrough()
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        // While the panel passes the mouse through, moves go to other apps: watch them to know
        // when the pointer comes back over the slab.
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.panel.updateMousePassThrough() }
        }
    }

    #if DEBUG
    func runAnimationTest() {
        var samples: [(TimeInterval, CGFloat, CGFloat)] = []
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 0.004, repeats: true) { [panel] _ in
            samples.append((CACurrentMediaTime() - start, panel.frame.height, panel.frame.maxY))
        }
        RunLoop.main.add(timer, forMode: .common)
        NotificationCenter.default.post(name: .debugToggleSettings, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NotificationCenter.default.post(name: .debugToggleSettings, object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            timer.invalidate()
            var last: CGFloat = -1
            var lastT: TimeInterval = 0
            var maxGap: TimeInterval = 0
            var lastTop: CGFloat = -1
            for (t, h, top) in samples {
                if t - lastT > 0.03 { print(String(format: "gap %.1f ms ending at %.3f", (t - lastT) * 1000, t)) }
                maxGap = max(maxGap, t - lastT)
                lastT = t
                if h != last || top != lastTop { print(String(format: "%.3f  h %.1f  top %.1f", t, h, top)); last = h; lastTop = top }
            }
            print(String(format: "samples %d, longest main-thread gap %.1f ms", samples.count, maxGap * 1000))
            exit(0)
        }
    }
    #endif

    func close() {
        guard panel.isVisible else { return }
        closedAt = Date()
        item.button?.highlight(false)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
        clickMonitor = nil
        moveMonitor = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }
}

/// What the menu bar icon says about the fans.
struct MenuBarState {
    let symbol: String
    let description: String

    @MainActor
    init(_ model: AppModel) {
        switch model.helperState {
        case .connected, .unknown:
            break
        default:
            symbol = "fan.badge.automatic"
            description = "FanControl: помощник недоступен, вентиляторами управляет macOS"
            return
        }
        if !model.fans.isEmpty, model.fans.allSatisfy({ $0.actualRPM < 100 }) {
            symbol = "fan.slash.fill"
            description = model.lidClosed ? "FanControl: крышка закрыта, вентиляторы остановлены"
                                          : "FanControl: вентиляторы остановлены"
        } else {
            symbol = "fan.fill"
            description = "FanControl: вентиляторы работают"
        }
    }
}
