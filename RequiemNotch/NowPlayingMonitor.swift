import SwiftUI
import AppKit
import Combine
import MediaRemoteAdapter

// MARK: - Слежение за музыкой и видео (любой плеер: Музыка, Spotify, YouTube, VLC…)

final class NowPlayingMonitor: ObservableObject {
    /// Информация о текущем треке (nil — ничего не играет)
    @Published private(set) var payload: TrackInfo.Payload?

    /// Вызывается при смене трека или старте воспроизведения
    var onTrackChanged: (() -> Void)?

    private let controller = MediaController()
    private var lastTrackKey: String?
    private var restartAttempts = 0

    var hasMedia: Bool { !(payload?.title ?? "").isEmpty }
    var isPlaying: Bool { payload?.isPlaying ?? ((payload?.playbackRate ?? 0) > 0) }
    /// Длительность в секундах (0 — неизвестна, например у стримов)
    var duration: Double { (payload?.durationMicros ?? 0) / 1_000_000 }

    init() {
        controller.onTrackInfoReceived = { [weak self] info in
            DispatchQueue.main.async { self?.handle(info) }
        }
        // Если фоновый процесс-слушатель упал — пробуем перезапустить (не больше 5 раз)
        controller.onListenerTerminated = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let self, self.restartAttempts < 5 else { return }
                self.restartAttempts += 1
                self.controller.startListening()
            }
        }
    }

    func start() {
        controller.startListening()
    }

    private func handle(_ info: TrackInfo?) {
        let wasPlaying = isPlaying
        payload = info?.payload
        restartAttempts = 0

        let key = payload.map { "\($0.title ?? "")|\($0.artist ?? "")" }
        let changed = key != nil && key != lastTrackKey
        lastTrackKey = key

        if hasMedia && isPlaying && (changed || !wasPlaying) {
            onTrackChanged?()
        }
    }

    // MARK: Управление
    func togglePlayPause() { controller.togglePlayPause() }
    func next() { controller.nextTrack() }
    func previous() { controller.previousTrack() }
}

// MARK: - Обложка

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

// MARK: - Анимированный эквалайзер

struct EqualizerBars: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (3 + Double(i)) + Double(i)
                    Capsule()
                        .fill(.white)
                        .frame(width: 3, height: isPlaying ? 4 + 10 * abs(sin(phase)) : 4)
                }
            }
            .frame(height: 14)
        }
    }
}

// MARK: - Мини-уведомление: обложка слева, эквалайзер справа

struct MusicCompactView: View {
    @EnvironmentObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        HStack {
            ArtworkView(image: nowPlaying.payload?.artwork, size: 20, corner: 5)
            Spacer()
            EqualizerBars(isPlaying: nowPlaying.isPlaying)
        }
    }
}

// MARK: - Плеер в раскрытом острове

struct NowPlayingView: View {
    @EnvironmentObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(image: nowPlaying.payload?.artwork, size: 64, corner: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.payload?.title ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(nowPlaying.payload?.artist ?? nowPlaying.payload?.applicationName ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if nowPlaying.duration > 0 {
                    PlaybackProgress()
                        .padding(.top, 6)
                }

                // Кнопки управления
                HStack(spacing: 22) {
                    Button { nowPlaying.previous() } label: {
                        Image(systemName: "backward.fill")
                    }
                    Button { nowPlaying.togglePlayPause() } label: {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .frame(width: 20)
                    }
                    Button { nowPlaying.next() } label: {
                        Image(systemName: "forward.fill")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .padding(.top, 6)
            }
        }
        .frame(width: 250, alignment: .leading)
    }
}

// MARK: - Полоса прогресса

struct PlaybackProgress: View {
    @EnvironmentObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        // Обновляем раз в секунду
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let duration = nowPlaying.duration
            let elapsed = min(nowPlaying.payload?.currentElapsedTime ?? 0, duration)
            let fraction = duration > 0 ? elapsed / duration : 0

            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text("-" + Self.format(duration - elapsed))
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
