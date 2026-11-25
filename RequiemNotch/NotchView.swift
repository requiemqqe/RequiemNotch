import SwiftUI
import Combine

struct NotchView: View {
    @EnvironmentObject var model: NotchModel

    var body: some View {
        let size: CGSize = model.isExpanded
            ? model.expandedSize
            : (model.activity != nil ? model.activitySize : model.notchSize)
        // Вогнутые «ушки» сверху и скругления снизу
        let top: CGFloat = model.isExpanded ? 14 : 6
        let bottom: CGFloat = model.isExpanded ? 28 : 10

        ZStack(alignment: .top) {
            NotchShape(topRadius: top, bottomRadius: bottom)
                .fill(.black)

            if model.isExpanded {
                ExpandedContent()
                    .padding(.top, model.notchSize.height + 4)
                    .padding(.horizontal, 24 + top)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            } else if let activity = model.activity {
                CompactActivityView(activity: activity)
                    .padding(.horizontal, 12 + top)
                    .frame(height: model.notchSize.height)
                    .transition(.opacity)
            }
        }
        // Ушки выходят за пределы выреза, поэтому добавляем их ширину
        .frame(width: size.width + top * 2, height: size.height)
        // Прижимаем к верху прозрачной панели
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Мини-уведомление (слева иконка, справа значение — как на iPhone)

struct CompactActivityView: View {
    let activity: NotchActivity
    @EnvironmentObject var battery: BatteryMonitor

    var body: some View {
        switch activity {
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

    private var symbol: String {
        if battery.isCharging { return "battery.100.bolt" }
        switch battery.level {
        case 88...:   return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default:      return "battery.0"
        }
    }

    private var tint: Color {
        if battery.isCharging { return .green }
        return battery.level <= 20 ? .red : .white
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text("\(battery.level)%")
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
    }
}

/// Сюда добавляешь свои модули: плеер, календарь, полку файлов и т.д.
struct ExpandedContent: View {
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date(), style: .time)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(Date(), format: .dateTime.weekday(.wide).day().month())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                BatteryBadge()
                    .padding(.top, 6)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.08))
                .frame(width: 220, height: 100)
                .overlay(Text("Now Playing").foregroundStyle(.secondary))
        }
        .foregroundStyle(.white)
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
