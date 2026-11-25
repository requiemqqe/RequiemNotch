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

final class NotchModel: ObservableObject {
    @Published var isExpanded = false
    /// Реальный размер выреза (или запасной, если экран без выреза)
    @Published var notchSize = CGSize(width: 200, height: 32)
    /// Размер раскрытого острова
    let expandedSize = CGSize(width: 520, height: 180)
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
    private let panel = NotchPanel()
    private var monitors: [Any] = []
    /// Панель большая и прозрачная; видимая часть рисуется в SwiftUI
    private let panelSize = CGSize(width: 640, height: 260)

    func show() {
        panel.contentView = NSHostingView(rootView: NotchView().environmentObject(model))
        reposition()
        panel.ignoresMouseEvents = true   // прозрачная часть не должна мешать кликам
        panel.orderFrontRegardless()

        let handler: (NSEvent) -> Void = { [weak self] _ in self?.updateHover() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { e in
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

    // Отложенное раскрытие/сворачивание (защита от дёрганья)
    private var hoverWork: DispatchWorkItem?
    private var pendingTarget: Bool?
    private var openDelay: Double {
           UserDefaults.standard.object(forKey: "openDelay") as? Double ?? 0.12
       }
       private var closeDelay: Double {
           UserDefaults.standard.object(forKey: "closeDelay") as? Double ?? 0.30
       }  // сек до сворачивания

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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            model.isExpanded = value
        }
        panel.ignoresMouseEvents = !value
    }
}
