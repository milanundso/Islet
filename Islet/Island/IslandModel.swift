import AppKit
import Combine

enum IslandPresentation: Equatable {
    case idle
    case music
    case activity
    case expanded
}

enum TransientActivity: Equatable {
    case volume(level: Float, isMuted: Bool)
    case power(level: Int, isPluggedIn: Bool)
}

final class IslandModel: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var transientActivity: TransientActivity?
    @Published var notchSize = CGSize(width: 190, height: 32)
    @Published var hasNotch = true

    let nowPlaying = NowPlayingMonitor()
    let musicSideWidth: CGFloat = 44
    let activitySideWidth: CGFloat = 74

    private let volumeMonitor = VolumeMonitor()
    private let powerMonitor = PowerMonitor()
    private var isHovering = false
    private var hoverWork: DispatchWorkItem?
    private var dismissWork: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()

    var presentation: IslandPresentation {
        if isExpanded { return .expanded }
        if transientActivity != nil { return .activity }
        if nowPlaying.track != nil && nowPlaying.isPlaying { return .music }
        return .idle
    }

    var islandSize: CGSize {
        switch presentation {
        case .idle:
            return notchSize
        case .music:
            return CGSize(width: notchSize.width + musicSideWidth * 2, height: notchSize.height)
        case .activity:
            return CGSize(width: notchSize.width + activitySideWidth * 2, height: notchSize.height)
        case .expanded:
            if nowPlaying.track == nil {
                return CGSize(width: max(notchSize.width + 120, 320), height: notchSize.height + 58)
            }
            return CGSize(width: max(notchSize.width + 200, 400), height: notchSize.height + 164)
        }
    }

    func start() {
        nowPlaying.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        nowPlaying.start()

        volumeMonitor.onChange = { [weak self] level, isMuted in
            guard UserDefaults.standard.bool(forKey: SettingsKey.showVolume) else { return }
            self?.show(.volume(level: level, isMuted: isMuted))
        }
        volumeMonitor.start()

        powerMonitor.onChange = { [weak self] status in
            guard UserDefaults.standard.bool(forKey: SettingsKey.showCharging) else { return }
            self?.show(.power(level: status.level, isPluggedIn: status.isPluggedIn))
        }
        powerMonitor.start()
    }

    func show(_ activity: TransientActivity) {
        transientActivity = activity
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.transientActivity = nil
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    func updateHover(_ isInside: Bool) {
        guard isInside != isHovering else { return }
        isHovering = isInside
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyHover()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isInside ? 0.12 : 0.3), execute: work)
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func applyHover() {
        if isHovering {
            guard UserDefaults.standard.bool(forKey: SettingsKey.expandOnHover) else { return }
            expand()
        } else {
            isExpanded = false
        }
    }
}
