import SwiftUI
import Combine

struct NotchView: View {
    @EnvironmentObject var model: NotchModel

    var body: some View {
        let size = model.isExpanded ? model.expandedSize : model.notchSize
        let radius: CGFloat = model.isExpanded ? 28 : 10

        ZStack(alignment: .top) {
            // Чёрная «капля», сливающаяся с вырезом
            UnevenRoundedRectangle(bottomLeadingRadius: radius,
                                   bottomTrailingRadius: radius)
                .fill(.black)

            if model.isExpanded {
                ExpandedContent()
                    .padding(.top, model.notchSize.height + 4)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .frame(width: size.width, height: size.height)
        // Прижимаем к верху прозрачной панели
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
