import AppKit
import SwiftUI

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
}

enum MediaSource: String, CaseIterable {
    case spotify
    case appleMusic

    var bundleIdentifier: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .appleMusic: return "com.apple.Music"
        }
    }

    var changeNotificationName: String {
        switch self {
        case .spotify: return "com.spotify.client.PlaybackStateChanged"
        case .appleMusic: return "com.apple.Music.playerInfo"
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    var snapshotScript: String {
        let durationExpression = self == .spotify ? "(duration of current track) / 1000" : "duration of current track"
        let artworkExpression = self == .spotify ? "artwork url of current track" : "\"\""
        return """
        tell application id "\(bundleIdentifier)"
            try
                if player state is stopped then return {"stopped"}
                set stateText to "paused"
                if player state is playing then set stateText to "playing"
                return {stateText, name of current track, artist of current track, album of current track, \(durationExpression), player position, \(artworkExpression)}
            on error
                return {"stopped"}
            end try
        end tell
        """
    }

    func commandScript(_ command: String) -> String {
        "tell application id \"\(bundleIdentifier)\" to \(command)"
    }
}

private struct PlayerSnapshot {
    var track: Track
    var isPlaying: Bool
    var position: Double
    var artworkAddress: String?
}

final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var backdrop: NSImage?
    @Published private(set) var accentColor = Color.white
    @Published private(set) var anchorPosition = 0.0

    private(set) var source: MediaSource?
    private var anchorDate = Date()
    private var pollTimer: Timer?
    private var artworkRequest = 0

    func start() {
        for candidate in MediaSource.allCases {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(candidate.changeNotificationName),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh(candidate)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAll()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
        refreshAll()
    }

    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        guard isPlaying else { return anchorPosition }
        return min(anchorPosition + date.timeIntervalSince(anchorDate), track.duration)
    }

    func togglePlayback() {
        send("playpause")
    }

    func skipForward() {
        send("next track")
    }

    func skipBackward() {
        send("previous track")
    }

    func seek(to position: Double) {
        guard let source else { return }
        AppleScriptRunner.run(source.commandScript("set player position to \(Int(position))"), isReusable: false)
        anchorDate = Date()
        anchorPosition = position
    }

    func openSourceApplication() {
        guard let source, let applicationLocation = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: applicationLocation, configuration: NSWorkspace.OpenConfiguration())
    }

    private func send(_ command: String) {
        guard let source, source.isRunning else { return }
        AppleScriptRunner.run(source.commandScript(command))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refresh(source)
        }
    }

    private func refreshAll() {
        if let source {
            refresh(source)
        }
        for candidate in MediaSource.allCases where candidate != source {
            refresh(candidate)
        }
    }

    private func refresh(_ candidate: MediaSource) {
        guard candidate.isRunning, let snapshot = readSnapshot(from: candidate) else {
            if source == candidate {
                clear()
            }
            return
        }
        let shouldTakeOver = snapshot.isPlaying && !isPlaying
        if source == candidate || source == nil || shouldTakeOver {
            apply(snapshot, from: candidate)
        }
    }

    private func readSnapshot(from candidate: MediaSource) -> PlayerSnapshot? {
        guard let result = AppleScriptRunner.run(candidate.snapshotScript), result.numberOfItems >= 7 else { return nil }
        let stateText = result.atIndex(1)?.stringValue ?? "stopped"
        let title = result.atIndex(2)?.stringValue ?? ""
        guard stateText != "stopped", !title.isEmpty else { return nil }
        let loadedTrack = Track(
            title: title,
            artist: result.atIndex(3)?.stringValue ?? "",
            album: result.atIndex(4)?.stringValue ?? "",
            duration: result.atIndex(5)?.doubleValue ?? 0
        )
        return PlayerSnapshot(
            track: loadedTrack,
            isPlaying: stateText == "playing",
            position: result.atIndex(6)?.doubleValue ?? 0,
            artworkAddress: result.atIndex(7)?.stringValue
        )
    }

    private func apply(_ snapshot: PlayerSnapshot, from candidate: MediaSource) {
        let expectedPosition = position(at: Date())
        let hasTrackChanged = snapshot.track != track || source != candidate
        let hasStateChanged = snapshot.isPlaying != isPlaying
        source = candidate
        if hasTrackChanged {
            track = snapshot.track
        }
        if hasStateChanged {
            isPlaying = snapshot.isPlaying
        }
        if hasTrackChanged || hasStateChanged || abs(expectedPosition - snapshot.position) > 1.5 {
            anchorDate = Date()
            anchorPosition = snapshot.position
        }
        if hasTrackChanged {
            loadArtwork(for: candidate, artworkAddress: snapshot.artworkAddress)
        }
    }

    private func clear() {
        source = nil
        track = nil
        isPlaying = false
        artworkRequest += 1
        setArtwork(nil)
    }

    private func loadArtwork(for candidate: MediaSource, artworkAddress: String?) {
        artworkRequest += 1
        let request = artworkRequest
        switch candidate {
        case .spotify:
            guard let artworkAddress, let artworkLocation = URL(string: artworkAddress) else {
                setArtwork(nil)
                return
            }
            URLSession.shared.dataTask(with: artworkLocation) { [weak self] data, _, _ in
                let image = data.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async {
                    guard let self, self.artworkRequest == request else { return }
                    self.setArtwork(image)
                }
            }.resume()
        case .appleMusic:
            let image = readMusicArtwork()
            setArtwork(image)
            guard image == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.artworkRequest == request else { return }
                self.setArtwork(self.readMusicArtwork())
            }
        }
    }

    private func readMusicArtwork() -> NSImage? {
        let script = MediaSource.appleMusic.commandScript("get raw data of artwork 1 of current track")
        guard MediaSource.appleMusic.isRunning, let result = AppleScriptRunner.run(script) else { return nil }
        return NSImage(data: result.data)
    }

    private func setArtwork(_ image: NSImage?) {
        artwork = image
        backdrop = image?.softened(sigma: 7)
        accentColor = image?.accentColor ?? .white
    }
}
