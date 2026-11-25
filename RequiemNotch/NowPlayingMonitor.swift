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
    /// Состояние ⏯ сразу после нажатия — не ждём, пока плеер подтвердит
    @Published private var optimisticPlaying: Bool?
    private var optimisticResetWork: DispatchWorkItem?

    var hasMedia: Bool { !(payload?.title ?? "").isEmpty }
    var isPlaying: Bool { optimisticPlaying ?? reportedPlaying }
    /// Что сообщает сам плеер
    private var reportedPlaying: Bool { payload?.isPlaying ?? ((payload?.playbackRate ?? 0) > 0) }
    /// Длительность в секундах (0 — неизвестна, например у стримов)
    var duration: Double { (payload?.durationMicros ?? 0) / 1_000_000 }
    /// nil — плеер не поддерживает перемешивание/повтор (например, YouTube)
    var shuffleMode: TrackInfo.ShuffleMode? { payload?.shuffleMode }
    var repeatMode: TrackInfo.RepeatMode? { payload?.repeatMode }

    /// Иконка приложения, которое сейчас играет
    var sourceAppIcon: NSImage? {
        guard let url = sourceAppURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var sourceAppURL: URL? {
        guard let id = payload?.bundleIdentifier else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

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
        // Плеер подтвердил новое состояние — «опережающее» больше не нужно
        if let optimistic = optimisticPlaying, reportedPlaying == optimistic {
            optimisticPlaying = nil
        }

        let key = payload.map { "\($0.title ?? "")|\($0.artist ?? "")" }
        let changed = key != nil && key != lastTrackKey
        lastTrackKey = key

        if hasMedia && isPlaying && (changed || !wasPlaying) {
            onTrackChanged?()
        }
    }

    // MARK: Управление
    func togglePlayPause() {
        // Меняем иконку сразу, а плеер догонит
        optimisticPlaying = !isPlaying
        controller.togglePlayPause()
        // Если плеер так и не ответил — через 2 с вернёмся к его реальному состоянию
        optimisticResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.optimisticPlaying = nil }
        optimisticResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
    func next() { controller.nextTrack() }
    func previous() { controller.previousTrack() }
    func seek(to seconds: Double) { controller.setTime(seconds: seconds) }
    func skipForward() { skip(by: 15) }
    func skipBackward() { skip(by: -15) }

    /// ±15 с через переход на позицию: Spotify и браузеры не понимают
    /// системную команду «перемотать на 15 с», а переход на позицию — понимают
    private func skip(by delta: Double) {
        let current = payload?.currentElapsedTime ?? 0
        var target = max(0, current + delta)
        if duration > 0 { target = min(target, duration - 1) }
        seek(to: target)
    }
    func toggleShuffle() { controller.toggleShuffle() }
    func toggleRepeat() { controller.toggleRepeat() }

    /// Открыть приложение, которое играет (Музыка, Spotify, браузер…)
    func openSourceApp() {
        guard let url = sourceAppURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // Обложка: клик открывает приложение-источник
                Button { nowPlaying.openSourceApp() } label: {
                    ArtworkView(image: nowPlaying.payload?.artwork, size: 52, corner: 10)
                        .overlay(alignment: .bottomTrailing) {
                            if let icon = nowPlaying.sourceAppIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .shadow(color: .black.opacity(0.5), radius: 2)
                                    .offset(x: 5, y: 5)
                            }
                        }
                }
                .buttonStyle(.pressable)
                .help("Open source app")
                // Новый трек — обложка плавно сменяется
                .id(nowPlaying.payload?.title)
                .transition(.blurFade)

                VStack(alignment: .leading, spacing: 1) {
                    Text(nowPlaying.payload?.title ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .contentTransition(.interpolate)
                    Text(nowPlaying.payload?.artist ?? nowPlaying.payload?.applicationName ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.interpolate)

                    if nowPlaying.duration > 0 {
                        PlaybackProgress()
                            .padding(.top, 4)
                    }
                }
            }

            PlayerControls()
        }
        .frame(width: 250, alignment: .leading)
        .animation(NotchAnimation.content, value: nowPlaying.payload?.title)
    }
}

// MARK: - Кнопки управления

struct PlayerControls: View {
    @EnvironmentObject var nowPlaying: NowPlayingMonitor
    @AppStorage("showSkipButtons") private var showSkipButtons = false
    /// Длительность анимации ⏸ ↔ ▶︎ (настройки → Media), 0 — без анимации
    @AppStorage("playPauseAnimation") private var playPauseAnimation = 0.15

    var body: some View {
        HStack(spacing: 0) {
            // Перемешивание (если плеер поддерживает)
            if let shuffle = nowPlaying.shuffleMode {
                Button { nowPlaying.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(shuffle == .off ? Color.secondary : Color.white)
                }
                .help("Shuffle")
            } else {
                Color.clear.frame(width: 16, height: 1)
            }

            Spacer(minLength: 0)

            if showSkipButtons {
                Button { nowPlaying.skipBackward() } label: {
                    Image(systemName: "gobackward.15")
                }
                .help("Back 15 seconds")
                Spacer(minLength: 0)
            }

            Button { nowPlaying.previous() } label: {
                Image(systemName: "backward.fill")
            }
            .help("Previous")

            Spacer(minLength: 0)

            Button { nowPlaying.togglePlayPause() } label: {
                Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .frame(width: 22)
                    // Смена ⏸ ↔ ▶︎ — скорость из настроек
                    .contentTransition(playPauseAnimation > 0
                        ? .symbolEffect(.replace, options: .speed(0.4 / playPauseAnimation))
                        : .identity)
                    .animation(playPauseAnimation > 0 ? .easeOut(duration: playPauseAnimation) : nil,
                               value: nowPlaying.isPlaying)
            }
            .help("Play / Pause")

            Spacer(minLength: 0)

            Button { nowPlaying.next() } label: {
                Image(systemName: "forward.fill")
            }
            .help("Next")

            if showSkipButtons {
                Spacer(minLength: 0)
                Button { nowPlaying.skipForward() } label: {
                    Image(systemName: "goforward.15")
                }
                .help("Forward 15 seconds")
            }

            Spacer(minLength: 0)

            // Повтор (если плеер поддерживает)
            if let repeatMode = nowPlaying.repeatMode {
                Button { nowPlaying.toggleRepeat() } label: {
                    Image(systemName: repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundStyle(repeatMode == .off ? Color.secondary : Color.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                .help("Repeat")
            } else {
                Color.clear.frame(width: 16, height: 1)
            }
        }
        .buttonStyle(.pressable)
        .font(.system(size: 14, weight: .medium))
        .frame(height: 24)
        .animation(NotchAnimation.content, value: showSkipButtons)
    }
}

// MARK: - Полоса прогресса с перемоткой

struct PlaybackProgress: View {
    @EnvironmentObject var nowPlaying: NowPlayingMonitor
    /// Позиция, которую сейчас тянут мышью (0…1), nil — не тянут
    @State private var scrubFraction: Double? = nil
    @State private var hovering = false
    /// Длительность утолщения полосы при наведении (настройки → Media), 0 — без анимации
    @AppStorage("progressHoverAnimation") private var hoverAnimation = 0.12

    var body: some View {
        // Обновляем раз в секунду
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let duration = nowPlaying.duration
            let elapsed = min(nowPlaying.payload?.currentElapsedTime ?? 0, duration)
            let liveFraction = duration > 0 ? elapsed / duration : 0
            let fraction = scrubFraction ?? liveFraction
            let shown = fraction * duration
            let thick = hovering || scrubFraction != nil

            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white)
                            .frame(width: geo.size.width * fraction)
                            // Пока тянем — без анимации, иначе едет непрерывно
                            .animation(scrubFraction == nil ? .linear(duration: 1) : nil, value: fraction)
                    }
                    .frame(height: thick ? 7 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                scrubFraction = min(max(value.location.x / geo.size.width, 0), 1)
                            }
                            .onEnded { value in
                                let target = min(max(value.location.x / geo.size.width, 0), 1)
                                nowPlaying.seek(to: target * duration)
                                // Держим позицию, пока плеер не пришлёт новое время
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    scrubFraction = nil
                                }
                            }
                    )
                }
                .frame(height: 10)
                .onHover { hovering = $0 }
                .animation(hoverAnimation > 0 ? .easeOut(duration: hoverAnimation) : nil, value: thick)

                HStack {
                    Text(verbatim: Self.format(shown))
                    Spacer()
                    Text(verbatim: "-" + Self.format(duration - shown))
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
