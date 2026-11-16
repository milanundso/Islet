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

struct LockScreenPlayerView: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        PlayerContent(nowPlaying: nowPlaying)
            .padding(20)
            .frame(width: 380)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class LockScreenController {
    private static let windowSize = CGSize(width: 440, height: 230)
    private let nowPlaying: NowPlayingMonitor
    private let window: NSWindow
    private var isLocked = false
    private var hasTrack = false
    private var subscriptions = Set<AnyCancellable>()

    init(nowPlaying: NowPlayingMonitor) {
        self.nowPlaying = nowPlaying
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: LockScreenController.windowSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = FirstMouseHostingView(rootView: LockScreenPlayerView(nowPlaying: nowPlaying))
        SkyLightBridge.moveAboveLockScreen(window)

        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.isLocked = true
            self?.updateVisibility()
        }
        distributedCenter.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.isLocked = false
            self?.updateVisibility()
        }
        nowPlaying.$track
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.hasTrack = track != nil
                self?.updateVisibility()
            }
            .store(in: &subscriptions)
    }

    private func updateVisibility() {
        let isEnabled = UserDefaults.standard.bool(forKey: SettingsKey.showLockScreenPlayer)
        guard isLocked, hasTrack, isEnabled else {
            window.orderOut(nil)
            return
        }
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        if let screen {
            let origin = CGPoint(
                x: screen.frame.midX - LockScreenController.windowSize.width / 2,
                y: screen.frame.minY + screen.frame.height * 0.2
            )
            window.setFrameOrigin(origin)
        }
        window.orderFrontRegardless()
    }
}
