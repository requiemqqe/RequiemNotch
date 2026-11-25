import SwiftUI

// MARK: - Все анимации острова в одном месте
// Меняешь цифры здесь — меняется поведение во всём приложении

enum NotchAnimation {
    /// Раскрытие острова
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Сворачивание острова
    static let close = Animation.spring(response: 0.32, dampingFraction: 0.92)
    /// Появление мини-уведомления
    static let activityIn = Animation.spring(response: 0.45, dampingFraction: 0.72)
    /// Исчезновение мини-уведомления
    static let activityOut = Animation.spring(response: 0.35, dampingFraction: 0.9)
    /// Появление содержимого (чуть позже формы)
    static let contentIn = Animation.easeOut(duration: 0.28).delay(0.1)
    /// Исчезновение содержимого (быстрее формы)
    static let contentOut = Animation.easeIn(duration: 0.12)
    /// Смены внутри острова: трек, часы ↔ плеер, полка
    static let content = Animation.smooth(duration: 0.3)
}

// MARK: - Переход «из размытия» как в iOS

struct BlurFadeModifier: ViewModifier {
    /// 0 — полностью виден, 1 — скрыт
    let amount: Double

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .blur(radius: 8 * amount)
            .scaleEffect(1 - 0.04 * amount, anchor: .top)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFadeModifier(amount: 1),
                  identity: BlurFadeModifier(amount: 0))
    }
}

// MARK: - Кнопка, которая «вдавливается» при нажатии

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6),
                       value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
