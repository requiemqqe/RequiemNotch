import SwiftUI
import ServiceManagement

// MARK: - Меню в строке меню

struct MenuBarContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Настройки…") {
            NSApp.activate()          // вывести окно настроек на передний план
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Выйти из RequiemNotch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - Окно настроек

struct SettingsView: View {
    @AppStorage("openDelay") private var openDelay = 0.12
    @AppStorage("closeDelay") private var closeDelay = 0.30

    var body: some View {
        Form {
            Section("Общие") {
                LaunchAtLoginToggle()
            }

            Section("Поведение острова") {
                LabeledContent("Задержка раскрытия") {
                    Slider(value: $openDelay, in: 0...0.5, step: 0.02)
                    Text("\(openDelay, specifier: "%.2f") с")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
                LabeledContent("Задержка сворачивания") {
                    Slider(value: $closeDelay, in: 0...1, step: 0.05)
                    Text("\(closeDelay, specifier: "%.2f") с")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}

// MARK: - Автозапуск при входе в систему

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Запускать при входе в систему", isOn: $enabled)
            .onChange(of: enabled) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Не получилось — вернуть переключатель в реальное состояние
                    enabled = SMAppService.mainApp.status == .enabled
                    print("Автозапуск: \(error)")
                }
            }
    }
}
