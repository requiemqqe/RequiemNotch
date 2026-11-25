import SwiftUI
import Combine

struct NotchView: View {
    @EnvironmentObject var model: NotchModel
    /// Подгонка высоты мини-уведомления под вырез (в настройках)
    @AppStorage("activityHeightAdjust") private var heightAdjust: Double = 0

    var body: some View {
        let activityHeight = model.notchSize.height + heightAdjust
        let size: CGSize = model.isExpanded
            ? model.expandedSize
            : (model.activity != nil
               ? CGSize(width: model.activitySize.width, height: activityHeight)
               : model.notchSize)
        // Вогнутые «ушки» сверху и скругления снизу
        let top: CGFloat = model.isExpanded ? 14 : 6
        let bottom: CGFloat = model.isExpanded ? 28 : 10

        ZStack(alignment: .top) {
            NotchShape(topRadius: top, bottomRadius: bottom)
                .fill(.black)

            if model.isExpanded {
                VStack(spacing: 4) {
                    // Верхняя строка по бокам выреза: дата и батарея
                    ExpandedHeader()
                        .frame(height: model.notchSize.height)
                    ExpandedContent()
                }
                .padding(.horizontal, 24 + top)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            } else if let activity = model.activity {
                CompactActivityView(activity: activity)
                    .padding(.horizontal, 12 + top)
                    .frame(height: activityHeight)
                    .transition(.opacity)
            }
        }
        // Ушки выходят за пределы выреза, поэтому добавляем их ширину
        .frame(width: size.width + top * 2, height: size.height)
        // Прижимаем к верху прозрачной панели
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Форма как у Dynamic Island: вогнутые верхние углы, скруглённые нижние

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    // Чтобы радиусы плавно анимировались вместе с размером
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = topRadius
        let b = bottomRadius

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // левое вогнутое ушко
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        // левая сторона вниз
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        // левый нижний угол
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        // низ
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        // правый нижний угол
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        // правая сторона вверх
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        // правое вогнутое ушко
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
// MARK: - Мини-уведомление (слева иконка, справа значение — как на iPhone)

struct CompactActivityView: View {
    let activity: NotchActivity
    @EnvironmentObject var battery: BatteryMonitor

    var body: some View {
        switch activity {
        case .nowPlaying:
            MusicCompactView()
        case .charging:
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                    .symbolEffect(.pulse)
                Spacer()
                Text("\(battery.level)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Значок батареи для раскрытого острова

struct BatteryBadge: View {
    @EnvironmentObject var battery: BatteryMonitor
    @AppStorage("colorfulBattery") private var colorful = false

    var body: some View {
        HStack(spacing: 6) {
            BatteryIcon(
                level: battery.level,
                color: BatteryStyle.color(level: battery.level,
                                          pluggedIn: battery.isPluggedIn,
                                          lowPower: battery.isLowPower,
                                          colorful: colorful),
                charging: battery.isCharging,
                pluggedIn: battery.isPluggedIn
            )
            Text("\(battery.level)%")
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
    }
}

// MARK: - Цвет батареи в зависимости от заряда

enum BatteryStyle {
    static func color(level: Int, pluggedIn: Bool, lowPower: Bool, colorful: Bool) -> Color {
        if pluggedIn { return .green }      // подключено питание
        if lowPower { return .yellow }      // режим энергосбережения
        if colorful {
            switch level {
            case ...10: return .red
            case ...20: return .orange
            case ...50: return .yellow
            default:    return .green
            }
        }
        // Как на Mac: белая, красная при 10% и ниже
        return level <= 10 ? .red : .white
    }
}

// MARK: - Сам значок батареи, нарисованный кодом

struct BatteryIcon: View {
    let level: Int
    let color: Color
    let charging: Bool
    let pluggedIn: Bool

    // Размеры корпуса
    private let bodyWidth: CGFloat = 25
    private let bodyHeight: CGFloat = 12
    private let inset: CGFloat = 2

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                // Корпус
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(.white.opacity(0.5), lineWidth: 1)
                    .frame(width: bodyWidth, height: bodyHeight)

                // Заливка — ширина зависит от процента
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(2, (bodyWidth - inset * 2) * CGFloat(level) / 100),
                           height: bodyHeight - inset * 2)
                    .padding(.leading, inset)
                    .animation(.easeInOut(duration: 0.4), value: level)
                    .animation(.easeInOut(duration: 0.4), value: color)

                // Молния или вилка поверх заливки
                if charging || pluggedIn {
                    Image(systemName: charging ? "bolt.fill" : "powerplug.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 1)
                        .frame(width: bodyWidth, height: bodyHeight)
                }
            }

            // «Пипка» батареи справа
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.5))
                .frame(width: 2, height: 4)
        }
    }
}

/// Сюда добавляешь свои модули: плеер, календарь, полку файлов и т.д.
// MARK: - Верхняя строка раскрытого острова (по бокам выреза)

struct ExpandedHeader: View {
    var body: some View {
        HStack {
            // Дата слева (обновляется каждую минуту)
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.weekday(.abbreviated).day().month())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Батарея справа
            BatteryBadge()
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Большие часы (когда ничего не играет)

struct ClockView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                Text("Ничего не играет")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Сюда добавляешь свои модули: плеер, календарь, полку файлов и т.д.
struct ExpandedContent: View {
    @EnvironmentObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Слева — плеер, если что-то играет, иначе часы
            if nowPlaying.hasMedia {
                NowPlayingView()
            } else {
                ClockView()
            }
            Spacer(minLength: 0)
            ShelfView()
        }
        .foregroundStyle(.white)
    }
}
