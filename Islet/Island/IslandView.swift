import SwiftUI

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct BlurFade: ViewModifier {
    var radius: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel

    private let islandSpring = Animation.spring(response: 0.42, dampingFraction: 0.76)

    private var contentTransition: AnyTransition {
        .modifier(active: BlurFade(radius: 10, opacity: 0), identity: BlurFade(radius: 0, opacity: 1))
            .combined(with: .scale(scale: 0.92, anchor: .top))
    }

    var body: some View {
        let islandSize = model.islandSize
        let presentation = model.presentation
        let earRadius: CGFloat = presentation == .idle ? 0 : 7
        let bottomRadius: CGFloat = presentation == .expanded ? 28 : 11

        ZStack(alignment: .top) {
            content(for: presentation)
                .padding(.horizontal, earRadius)
        }
        .frame(width: islandSize.width + earRadius * 2, height: islandSize.height, alignment: .top)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: earRadius, bottomRadius: bottomRadius))
        .shadow(color: .black.opacity(presentation == .expanded ? 0.5 : 0), radius: 20, y: 10)
        .opacity(presentation == .idle && !model.hasNotch ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(islandSpring, value: presentation)
        .animation(islandSpring, value: islandSize)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func content(for presentation: IslandPresentation) -> some View {
        switch presentation {
        case .idle:
            Color.clear
        case .music:
            CompactMusicView(model: model)
                .transition(contentTransition)
        case .activity:
            if let activity = model.transientActivity {
                CompactActivityView(model: model, activity: activity)
                    .transition(contentTransition)
            }
        case .expanded:
            ExpandedIslandView(model: model)
                .transition(contentTransition)
        }
    }
}

struct CompactMusicView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: model.nowPlaying.artwork, cornerRadius: 6)
                .frame(width: 22, height: 22)
                .frame(width: model.musicSideWidth)
            Spacer(minLength: 0)
            EqualizerBars(color: model.nowPlaying.accentColor, isPlaying: model.nowPlaying.isPlaying)
                .frame(width: model.musicSideWidth)
        }
        .frame(height: model.notchSize.height)
        .contentShape(Rectangle())
        .onTapGesture {
            model.expand()
        }
    }
}

struct CompactActivityView: View {
    @ObservedObject var model: IslandModel
    var activity: TransientActivity

    var body: some View {
        HStack(spacing: 0) {
            leadingSymbol
                .font(.system(size: 13, weight: .semibold))
                .frame(width: model.activitySideWidth - 12, alignment: .leading)
                .padding(.leading, 12)
            Spacer(minLength: 0)
            trailingDetail
                .frame(width: model.activitySideWidth - 12, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .frame(height: model.notchSize.height)
    }

    @ViewBuilder
    private var leadingSymbol: some View {
        switch activity {
        case .volume(let level, let isMuted):
            Image(systemName: volumeSymbol(level: level, isMuted: isMuted))
                .foregroundStyle(.white)
        case .power(_, let isPluggedIn):
            Image(systemName: isPluggedIn ? "bolt.fill" : "battery.75percent")
                .foregroundStyle(isPluggedIn ? Color.green : Color.white)
        }
    }

    private func volumeSymbol(level: Float, isMuted: Bool) -> String {
        if isMuted || level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    @ViewBuilder
    private var trailingDetail: some View {
        switch activity {
        case .volume(let level, let isMuted):
            LevelBar(fraction: isMuted ? 0 : CGFloat(level))
                .frame(width: 52, height: 5)
        case .power(let level, let isPluggedIn):
            Text("\(level)%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(isPluggedIn ? Color.green : Color.white)
        }
    }
}

struct LevelBar: View {
    var fraction: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white).frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .animation(.easeOut(duration: 0.15), value: fraction)
    }
}

struct ExpandedIslandView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        Group {
            if model.nowPlaying.track != nil {
                PlayerContent(nowPlaying: model.nowPlaying)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                    Text("Nothing playing")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, model.notchSize.height + 6)
    }
}
