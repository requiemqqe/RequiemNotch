import SwiftUI
import AppKit
import Combine

// MARK: - Точка входа

@main
struct NotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Иконка в строке меню
        MenuBarExtra("RequiemNotch", systemImage: "capsule.fill") {
            MenuBarContent()
        }
        // Окно настроек
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Без иконки в Dock и без пункта меню (как у NotchNook)
        NSApp.setActivationPolicy(.accessory)
        // Запомнить язык запуска — по нему настройки решают, нужен ли перезапуск
        _ = AppLanguage.atLaunch

        let controller = NotchWindowController()
        controller.show()
        self.controller = controller

        // Подключили/отключили монитор, сменили разрешение — пересчитать позицию
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.controller?.reposition() }
    }
}

// MARK: - Модель состояния

/// Мини-уведомления, которые остров показывает сам (без наведения)
enum NotchActivity: Equatable {
    case charging
    case nowPlaying
}

final class NotchModel: ObservableObject {
    @Published var isExpanded = false
    /// Над островом сейчас тащат файл
    @Published var isDropTargeted = false
    /// Текущее мини-уведомление (nil — ничего не показываем)
    @Published var activity: NotchActivity? = nil
    /// Реальный размер выреза (или запасной, если экран без выреза)
    @Published var notchSize = CGSize(width: 200, height: 32)
    /// Размер раскрытого острова
    let expandedSize = CGSize(width: 600, height: 180)
    /// Размер острова с мини-уведомлением: вырез + по 80pt с каждой стороны
    var activitySize: CGSize {
        CGSize(width: notchSize.width + 160, height: notchSize.height)
    }
}

// MARK: - Размер выреза

extension NSScreen {
    /// nil, если у экрана нет выреза (внешний монитор, старые маки)
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea?.width,
              let right = auxiliaryTopRightArea?.width else { return nil }
        return CGSize(width: frame.width - left - right, height: safeAreaInsets.top)
    }
}

// MARK: - Панель поверх меню-бара

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        // Выше строки меню, чтобы перекрывать область выреза
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        acceptsMouseMovedEvents = true
        // Виден на всех рабочих столах и поверх полноэкранных приложений
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Контроллер: позиция + наведение мыши

final class NotchWindowController {
    let model = NotchModel()
    let battery = BatteryMonitor()
    let shelf = ShelfModel()
    let nowPlaying = NowPlayingMonitor()
    private let panel = NotchPanel()
    private var activityHideWork: DispatchWorkItem?
    private var monitors: [Any] = []
    /// Панель большая и прозрачная; видимая часть рисуется в SwiftUI
    private let panelSize = CGSize(width: 700, height: 260)

    func show() {
        panel.contentView = NSHostingView(rootView: NotchView()
            .environmentObject(model)
            .environmentObject(battery)
            .environmentObject(shelf)
            .environmentObject(nowPlaying))

        // Новый трек или старт воспроизведения — показать мини-уведомление
        nowPlaying.onTrackChanged = { [weak self] in
            guard Self.setting("showMusicActivity", default: true) else { return }
            self?.showActivity(.nowPlaying)
        }
        nowPlaying.start()

        // Подключили зарядку — показать мини-уведомление
        battery.onPluggedIn = { [weak self] in
            guard Self.setting("showChargingActivity", default: true) else { return }
            self?.showActivity(.charging)
        }
        // Кнопка «Preview» из настроек
        NotificationCenter.default.addObserver(
            forName: .testChargingActivity, object: nil, queue: .main
        ) { [weak self] _ in
            self?.showActivity(.charging)
        }

        reposition()
        panel.ignoresMouseEvents = true   // прозрачная часть не должна мешать кликам
        panel.orderFrontRegardless()

        let handler: (NSEvent) -> Void = { [weak self] _ in self?.updateHover() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp], handler: handler) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp], handler: { e in
            handler(e); return e
        }) {
            monitors.append(l)
        }
    }

    func reposition() {
        // Берём встроенный экран с вырезом, иначе основной
        guard let screen = NSScreen.screens.first(where: { $0.notchSize != nil }) ?? NSScreen.main else { return }
        model.notchSize = screen.notchSize ?? CGSize(width: 200, height: 32)
        let f = screen.frame
        panel.setFrame(NSRect(x: f.midX - panelSize.width / 2,
                              y: f.maxY - panelSize.height,
                              width: panelSize.width,
                              height: panelSize.height),
                       display: true)
    }

    /// Показать мини-уведомление на несколько секунд
    func showActivity(_ activity: NotchActivity, duration: Double = 3) {
        guard !model.isExpanded else { return }   // остров раскрыт — не мешаем
        activityHideWork?.cancel()
        withAnimation(NotchAnimation.activityIn) {
            model.activity = activity
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(NotchAnimation.activityOut) {
                self?.model.activity = nil
            }
        }
        activityHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: Наведение мыши

    // Отложенное раскрытие/сворачивание (защита от дёрганья)
    private var hoverWork: DispatchWorkItem?
    private var pendingTarget: Bool?

    // Задержки берутся из настроек (SettingsView), по умолчанию 0.12 и 0.3 сек
    private var openDelay: Double {
        UserDefaults.standard.object(forKey: "openDelay") as? Double ?? 0.12
    }
    private var closeDelay: Double {
        UserDefaults.standard.object(forKey: "closeDelay") as? Double ?? 0.30
    }

    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        let f = panel.frame
        // Зона срабатывания: чуть больше выреза в свёрнутом виде, весь остров — в раскрытом
        let size = model.isExpanded
            ? model.expandedSize
            : CGSize(width: model.notchSize.width + 20, height: model.notchSize.height + 6)
        // +10 сверху: у самого края экрана y курсора == верхней границе,
        // а NSRect.contains верхнюю границу не включает — отсюда были «прыжки»
        let hot = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                         width: size.width, height: size.height + 10)
        let inside = hot.contains(mouse)

        // Курсор там, где и должен быть — отменяем запланированное переключение
        guard inside != model.isExpanded else {
            cancelPending()
            return
        }
        // Такое переключение уже запланировано — ждём
        if pendingTarget == inside { return }

        cancelPending()
        pendingTarget = inside
        let work = DispatchWorkItem { [weak self] in
            self?.pendingTarget = nil
            // Пока зажата кнопка мыши (тащим файл) — не сворачиваем,
            // иначе перетаскивание с полки оборвётся. Свернёмся после отпускания.
            if !inside && NSEvent.pressedMouseButtons & 1 != 0 { return }
            self?.setExpanded(inside)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? openDelay : closeDelay), execute: work)
    }

    private func cancelPending() {
        hoverWork?.cancel()
        hoverWork = nil
        pendingTarget = nil
    }

    private func setExpanded(_ value: Bool) {
        withAnimation(value ? NotchAnimation.open : NotchAnimation.close) {
            model.isExpanded = value
        }
        panel.ignoresMouseEvents = !value

        // Лёгкий щелчок трекпада при раскрытии
        if value && Self.setting("hapticFeedback", default: true) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// Прочитать переключатель из настроек
    private static func setting(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}
