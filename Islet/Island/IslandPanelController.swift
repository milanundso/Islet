import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

final class IslandPanelController {
    private let model: IslandModel
    private let panel: IslandPanel
    private static let canvasSize = CGSize(width: 640, height: 320)
    private var mouseTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    init(model: IslandModel) {
        self.model = model
        panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: IslandPanelController.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = FirstMouseHostingView(rootView: IslandView(model: model))

        layout()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.layout()
        }

        let trackedEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: trackedEvents) { [weak self] _ in
            self?.trackMouse()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: trackedEvents) { [weak self] event in
            self?.trackMouse()
            return event
        }
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.trackMouse()
        }
    }

    private func layout() {
        guard let screen = targetScreen else { return }
        if screen.safeAreaInsets.top > 0, let leftArea = screen.auxiliaryTopLeftArea, let rightArea = screen.auxiliaryTopRightArea {
            model.hasNotch = true
            model.notchSize = CGSize(width: screen.frame.width - leftArea.width - rightArea.width, height: screen.safeAreaInsets.top)
        } else {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            model.hasNotch = false
            model.notchSize = CGSize(width: 180, height: max(menuBarHeight, 24))
        }
        let canvasSize = IslandPanelController.canvasSize
        let panelFrame = NSRect(
            x: screen.frame.midX - canvasSize.width / 2,
            y: screen.frame.maxY - canvasSize.height,
            width: canvasSize.width,
            height: canvasSize.height
        )
        panel.setFrame(panelFrame, display: true)
    }

    private func trackMouse() {
        guard let screen = targetScreen else { return }
        let islandSize = model.islandSize
        let tolerance: CGFloat = model.isExpanded ? 8 : 0
        let hotArea = CGRect(
            x: screen.frame.midX - islandSize.width / 2 - tolerance,
            y: screen.frame.maxY - islandSize.height - tolerance,
            width: islandSize.width + tolerance * 2,
            height: islandSize.height + tolerance + 4
        )
        let isInside = hotArea.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == isInside {
            panel.ignoresMouseEvents = !isInside
        }
        model.updateHover(isInside)
    }
}
