import SwiftUI

// MARK: - Иконки громкости и яркости в шапке острова с выезжающими ползунками

enum IslandControlKind: Equatable {
    case volume
    case brightness
}

/// Левая часть шапки: 🔊 ☀️ и дата (дата прячется, пока открыт ползунок)
struct HeaderLeading: View {
    @State private var active: IslandControlKind?
    @State private var brightnessAvailable = DisplayBrightness.isAvailable

    var body: some View {
        HStack(spacing: 10) {
            IslandSliderControl(kind: .volume, active: $active)
            if brightnessAvailable {
                IslandSliderControl(kind: .brightness, active: $active)
            }

            if active == nil {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.weekday(.abbreviated).day().month())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .transition(.blurFade)
            }
        }
        .animation(NotchAnimation.content, value: active)
    }
}

// MARK: - Иконка + ползунок, который выезжает при наведении

struct IslandSliderControl: View {
    let kind: IslandControlKind
    @Binding var active: IslandControlKind?

    @State private var value: Float = 0
    @State private var muted = false
    @State private var hovering = false
    @State private var dragging = false
    @State private var closeWork: DispatchWorkItem?

    private var isOpen: Bool { active == kind }

    private var symbol: String {
        switch kind {
        case .volume: return muted ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                // Клик по динамику — выключить/включить звук
                guard kind == .volume else { return }
                SystemVolume.isMuted.toggle()
                read()
            } label: {
                Image(systemName: symbol,
                      variableValue: kind == .volume && !muted ? Double(value) : nil)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .help(kind == .volume ? "Volume" : "Brightness")

            if isOpen {
                SmoothSlider(value: $value, dragging: $dragging) { newValue in
                    apply(newValue)
                }
                .frame(width: 100)
                .transition(.opacity.combined(with: .scale(scale: 0.5, anchor: .leading)))
            }
        }
        .foregroundStyle(isOpen ? Color.white : Color.secondary)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            closeWork?.cancel()
            if inside {
                read()
                active = kind
            } else {
                scheduleClose()
            }
        }
        // Отпустили ползунок уже за пределами — закрываем
        .onChange(of: dragging) { _, isDragging in
            if !isDragging && !hovering { scheduleClose() }
        }
    }

    private func scheduleClose() {
        let work = DispatchWorkItem {
            if !dragging && !hovering && active == kind { active = nil }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Прочитать текущий уровень из системы
    private func read() {
        switch kind {
        case .volume:
            value = SystemVolume.volume
            muted = SystemVolume.isMuted
        case .brightness:
            value = DisplayBrightness.value ?? 0
        }
    }

    /// Применить уровень к системе
    private func apply(_ newValue: Float) {
        switch kind {
        case .volume:
            if muted && newValue > 0 {
                SystemVolume.isMuted = false
                muted = false
            }
            SystemVolume.volume = newValue
        case .brightness:
            DisplayBrightness.value = newValue
        }
    }
}

// MARK: - Плавный ползунок

struct SmoothSlider: View {
    @Binding var value: Float
    @Binding var dragging: Bool
    let onChange: (Float) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white)
                    .frame(width: geo.size.width * CGFloat(value))
            }
            .frame(height: dragging ? 8 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        let newValue = Float(min(max(gesture.location.x / geo.size.width, 0), 1))
                        value = newValue
                        onChange(newValue)
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: 16)
        .animation(.easeOut(duration: 0.12), value: dragging)
    }
}
