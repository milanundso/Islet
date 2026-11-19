import SwiftUI
import CoreImage

extension NSImage {
    func softened(sigma: Double) -> NSImage? {
        guard let tiffData = tiffRepresentation, let original = CIImage(data: tiffData) else { return nil }
        let blurred = original.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: original.extent)
        guard let rendered = CIContext().createCGImage(blurred, from: original.extent) else { return nil }
        return NSImage(cgImage: rendered, size: original.extent.size)
    }
}

struct DriftingBackdrop: View {
    var image: NSImage?
    var accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    LinearGradient(colors: [accentColor.opacity(0.5), .black], startPoint: .top, endPoint: .bottom)
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(1.28 + 0.07 * sin(seconds * 0.31))
                            .offset(x: 42 * sin(seconds * 0.23), y: 30 * cos(seconds * 0.19))
                            .rotationEffect(.degrees(1.6 * sin(seconds * 0.13)))
                            .id(image)
                            .transition(.opacity)
                    }
                    LinearGradient(
                        colors: [.black.opacity(0.45), .black.opacity(0.12), .black.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .animation(.easeInOut(duration: 0.9), value: image)
            }
        }
        .background(Color.black)
    }
}

struct LockScreenClock: View {
    var accentColor: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(spacing: 0) {
                Text(timeline.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text(timeline.date, format: .dateTime.hour().minute())
                    .font(.system(size: 104, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, accentColor.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    )
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        }
    }
}

struct LockScreenPlayerCard: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(nowPlaying.track?.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(nowPlaying.track?.artist ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            PlaybackScrubber(nowPlaying: nowPlaying)
            PlaybackControls(nowPlaying: nowPlaying)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 320)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

struct LockScreenView: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    var onBackgroundTap: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let coverSide = min(geometry.size.height * 0.36, geometry.size.width * 0.3)
            ZStack {
                DriftingBackdrop(image: nowPlaying.backdrop, accentColor: nowPlaying.accentColor)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onBackgroundTap)

                VStack(spacing: 0) {
                    LockScreenClock(accentColor: nowPlaying.accentColor)
                        .padding(.top, geometry.size.height * 0.07)
                    Spacer(minLength: 16)
                    ArtworkView(image: nowPlaying.artwork, cornerRadius: 16)
                        .frame(width: coverSide, height: coverSide)
                        .shadow(color: .black.opacity(0.5), radius: 34, y: 18)
                        .scaleEffect(nowPlaying.isPlaying ? 1 : 0.9)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: nowPlaying.isPlaying)
                    LockScreenPlayerCard(nowPlaying: nowPlaying)
                        .padding(.top, 26)
                    Spacer(minLength: 16)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}
