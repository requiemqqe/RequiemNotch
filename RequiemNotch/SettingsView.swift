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

        Button("Тест: зарядка") {
            NotificationCenter.default.post(name: .testChargingActivity, object: nil)
        }

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
    @AppStorage("colorfulBattery") private var colorfulBattery = false
    @AppStorage("activityHeightAdjust") private var heightAdjust: Double = 0
    
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
            
            Section("Подгонка под вырез") {
                LabeledContent("Высота уведомлений") {
                    Slider(value: $heightAdjust, in: -6...6, step: 0.5)
                    Text("\(heightAdjust, specifier: "%+.1f") pt")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
                HStack {
                    Button("Показать тест") {
                        NotificationCenter.default.post(name: .testChargingActivity, object: nil)
                    }
                    Button("Сбросить") { heightAdjust = 0 }
                }
            }

            Section("Батарея") {
                Toggle("Цветная батарея", isOn: $colorfulBattery)
                Text("Зелёная → жёлтая ≤50% → оранжевая ≤20% → красная ≤10%. Выключено — как на Mac: белая, красная при ≤10%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
