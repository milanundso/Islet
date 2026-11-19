import AppKit
import SwiftUI
import Combine

enum SkyLightBridge {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsToSpace = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
    private static var lockScreenSpace: Int32?

    private static func function<Signature>(_ name: String, as signature: Signature.Type) -> Signature? {
        guard let library, let symbol = dlsym(library, name) else { return nil }
        return unsafeBitCast(symbol, to: signature)
    }

    static func moveAboveLockScreen(_ window: NSWindow) {
        guard let mainConnection = function("SLSMainConnectionID", as: MainConnection.self),
              let spaceCreate = function("SLSSpaceCreate", as: SpaceCreate.self),
              let spaceSetAbsoluteLevel = function("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let showSpaces = function("SLSShowSpaces", as: ShowSpaces.self),
              let addWindowsToSpace = function("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindowsToSpace.self) else { return }
        let connection = mainConnection()
        let space: Int32
        if let lockScreenSpace {
            space = lockScreenSpace
        } else {
            space = spaceCreate(connection, 1, 0)
            _ = spaceSetAbsoluteLevel(connection, space, 400)
            _ = showSpaces(connection, [space] as CFArray)
            lockScreenSpace = space
        }
        _ = addWindowsToSpace(connection, space, [window.windowNumber] as CFArray, 7)
    }
}

final class LockScreenController {
    private let nowPlaying: NowPlayingMonitor
    private let window: NSWindow
    private let typingQuietSeconds = 6.0
    private var isLocked = false
    private var hasTrack = false
    private var isShowing = false
    private var lockDate = Date()
    private var steppedAsideUntil = Date.distantPast
    private var activityTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    init(nowPlaying: NowPlayingMonitor) {
        self.nowPlaying = nowPlaying
        window = NSWindow(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = FirstMouseHostingView(rootView: LockScreenView(nowPlaying: nowPlaying) { [weak self] in
            self?.stepAside()
        })
        SkyLightBridge.moveAboveLockScreen(window)

        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.handleLockChange(isNowLocked: true)
        }
        distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.handleLockChange(isNowLocked: false)
        }
        nowPlaying.$track
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.hasTrack = track != nil
                self?.updateVisibility()
            }
            .store(in: &subscriptions)
    }

    private func handleLockChange(isNowLocked: Bool) {
        isLocked = isNowLocked
        lockDate = Date()
        steppedAsideUntil = .distantPast
        activityTimer?.invalidate()
        activityTimer = nil
        if isNowLocked {
            activityTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.updateVisibility()
            }
        }
        updateVisibility()
    }

    private func stepAside() {
        steppedAsideUntil = Date().addingTimeInterval(typingQuietSeconds)
        updateVisibility()
    }

    private var isUserTyping: Bool {
        let secondsSinceKey = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let secondsSinceLock = Date().timeIntervalSince(lockDate) - 1
        return secondsSinceKey < min(typingQuietSeconds, secondsSinceLock)
    }

    private func updateVisibility() {
        let isEnabled = UserDefaults.standard.bool(forKey: SettingsKey.showLockScreenPlayer)
        let shouldShow = isLocked && hasTrack && isEnabled && !isUserTyping && Date() > steppedAsideUntil
        guard shouldShow != isShowing else { return }
        isShowing = shouldShow
        if shouldShow {
            let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
            if let screen {
                window.setFrame(screen.frame, display: true)
            }
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.6
                window.animator().alphaValue = 1
            }
        } else {
            let fadeDuration = isLocked ? 0.25 : 0
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fadeDuration
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, !self.isShowing else { return }
                self.window.orderOut(nil)
            })
        }
    }
}
