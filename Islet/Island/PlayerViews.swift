import SwiftUI

struct ArtworkView: View {
    var image: NSImage?
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                Image(systemName: "music.note")
                    .resizable()
                    .scaledToFit()
                    .padding(.vertical, 5)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: image)
    }
}

struct EqualizerBars: View {
    var color: Color
    var isPlaying: Bool

    private let barCount = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { barIndex in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: barHeight(barIndex: barIndex, seconds: seconds))
                }
            }
            .frame(height: 16)
        }
    }

    private func barHeight(barIndex: Int, seconds: Double) -> CGFloat {
        guard isPlaying else { return 3 }
        let speed = 5.0 + Double(barIndex % 3) * 1.7
        let phase = Double(barIndex) * 1.3
        let wave = (sin(seconds * speed + phase) + sin(seconds * speed * 0.6 + phase * 2)) / 4 + 0.5
        return 3 + CGFloat(wave) * 13
    }
}

struct PlayerContent: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    nowPlaying.openSourceApplication()
                } label: {
                    ArtworkView(image: nowPlaying.artwork, cornerRadius: 14)
                        .frame(width: 64, height: 64)
                        .shadow(color: nowPlaying.accentColor.opacity(0.35), radius: 12, y: 4)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(nowPlaying.track?.title ?? "")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(nowPlaying.track?.artist ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                EqualizerBars(color: nowPlaying.accentColor, isPlaying: nowPlaying.isPlaying)
            }
            PlaybackScrubber(nowPlaying: nowPlaying)
            PlaybackControls(nowPlaying: nowPlaying)
        }
    }
}

struct PlaybackScrubber: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let duration = max(nowPlaying.track?.duration ?? 0, 1)
            let livePosition = nowPlaying.position(at: timeline.date)
            let fraction = dragFraction ?? min(max(livePosition / duration, 0), 1)

            HStack(spacing: 8) {
                Text(formatTime(fraction * duration))
                    .frame(width: 38, alignment: .leading)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white.opacity(0.9))
                            .frame(width: geometry.size.width * CGFloat(fraction))
                    }
                    .frame(height: dragFraction == nil ? 5 : 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let rawFraction = Double(drag.location.x / max(geometry.size.width, 1))
                                dragFraction = min(max(rawFraction, 0), 1)
                            }
                            .onEnded { _ in
                                if let dragFraction {
                                    nowPlaying.seek(to: dragFraction * duration)
                                }
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 14)
                Text("-" + formatTime(duration - fraction * duration))
                    .frame(width: 42, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
            .animation(.easeOut(duration: 0.15), value: dragFraction == nil)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let wholeSeconds = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }
}

struct PlaybackControls: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 36) {
            controlButton(symbol: "backward.fill", symbolSize: 18) {
                nowPlaying.skipBackward()
            }
            controlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", symbolSize: 26) {
                nowPlaying.togglePlayback()
            }
            controlButton(symbol: "forward.fill", symbolSize: 18) {
                nowPlaying.skipForward()
            }
        }
        .frame(height: 32)
    }

    private func controlButton(symbol: String, symbolSize: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 32)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}
