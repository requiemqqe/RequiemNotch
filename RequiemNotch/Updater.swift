import SwiftUI
import AppKit
import Combine
import Sparkle

// MARK: - Автообновления (Sparkle)
// Приложение раз в сутки смотрит файл appcast.xml на GitHub. Если там версия новее —
// предлагает скачать и установить её в один клик

final class Updater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Проверить сейчас (пункт меню и кнопка в настройках)
    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    // У приложения нет иконки в Dock — показываем окно обновления поверх всех
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        NSApp.activate()
    }
}

// MARK: - Пункт меню «Check for Updates…»

struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

// MARK: - Раздел в настройках

struct UpdatesSection: View {
    @ObservedObject private var updater = Updater.shared
    @State private var automatic = Updater.shared.automaticallyChecks

    var body: some View {
        Section("Updates") {
            Toggle(isOn: $automatic) {
                Text("Check for updates automatically")
                Text("RequiemNotch checks once a day and offers to install new versions.")
            }
            .onChange(of: automatic) { _, value in updater.automaticallyChecks = value }

            HStack {
                if let date = updater.lastCheck {
                    Text("Last checked \(date, format: .relative(presentation: .named))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}
