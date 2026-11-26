import SwiftUI
import AppKit
import ServiceManagement
import Combine
import ApplicationServices

// MARK: - Меню в строке меню

/// Ссылки проекта (поменяй, если переименуешь репозиторий)
enum AppLinks {
    static let github = URL(string: "https://github.com/requiemqqe/RequiemNotch")!
    static let feedback = URL(string: "https://github.com/requiemqqe/RequiemNotch/issues/new")!
}

struct MenuBarContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate()          // вывести окно настроек на передний план
            openSettings()
        }
        .keyboardShortcut(",")

        CheckForUpdatesButton()

        Button("Welcome Guide") {
            WelcomeWindow.show()
        }

        Button("Send Feedback…") {
            NSWorkspace.shared.open(AppLinks.feedback)
        }

        Divider()

        Button("Quit RequiemNotch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - Окно настроек (вкладки)

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            IslandSettings()
                .tabItem { Label("Island", systemImage: "capsule") }
            MediaSettings()
                .tabItem { Label("Media", systemImage: "play.circle") }
            BatterySettings()
                .tabItem { Label("Battery", systemImage: "bolt.fill") }
            DevicesSettings()
                .tabItem { Label("Devices", systemImage: "headphones") }
            ClipboardSettings()
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            HUDSettings()
                .tabItem { Label("HUD", systemImage: "speaker.wave.2") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 700, height: 500)
    }
}

// MARK: - Вкладка «General»: язык, автозапуск

struct GeneralSettings: View {
    @AppStorage("appLanguage") private var language: AppLanguage = .system
    /// Перезапуск нужен, только если выбран не тот язык, с которым приложение запущено
    private var needsRestart: Bool { language != AppLanguage.atLaunch }

    var body: some View {
        Form {
            Section("Language") {
                Picker(selection: $language) {
                    ForEach(AppLanguage.allCases) { lang in
                        lang.label.tag(lang)
                    }
                } label: {
                    Text("Language")
                    Text("Choose the interface language. The app restarts to apply it.")
                }
                .onChange(of: language) { _, newValue in
                    newValue.apply()
                }

                if needsRestart {
                    HStack {
                        Label("Restart required to apply the language.", systemImage: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart now") { AppLanguage.relaunch() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section("Startup") {
                LaunchAtLoginToggle()
            }

            UpdatesSection()
        }
        .formStyle(.grouped)
        .animation(.easeInOut(duration: 0.2), value: needsRestart)
    }
}

// MARK: - Вкладка «Island»: поведение и подгонка

struct IslandSettings: View {
    @AppStorage("openDelay") private var openDelay = 0.12
    @AppStorage("closeDelay") private var closeDelay = 0.30
    @AppStorage("hapticFeedback") private var haptics = true
    @AppStorage("showMirrorButton") private var showMirrorButton = true
    @AppStorage("nonNotchMode") private var nonNotchMode: NonNotchMode = .hover
    @AppStorage("activityHeightAdjust") private var heightAdjust: Double = 0

    var body: some View {
        Form {
            Section("Behavior") {
                LabeledContent {
                    SliderValue(value: $openDelay, range: 0...0.5, step: 0.02, unit: "s")
                } label: {
                    Text("Open delay")
                    Text("How long to hold the cursor over the notch before the island opens.")
                }

                LabeledContent {
                    SliderValue(value: $closeDelay, range: 0...1, step: 0.05, unit: "s")
                } label: {
                    Text("Close delay")
                    Text("How long the island stays open after the cursor leaves it.")
                }

                Toggle(isOn: $haptics) {
                    Text("Haptic feedback")
                    Text("A light tap on the trackpad when the island opens.")
                }
            }

            Section("Camera") {
                Toggle(isOn: $showMirrorButton) {
                    Text("Mirror button")
                    Text("Show a camera button in the island to quickly check how you look before a call.")
                }
            }

            Section("Macs without a notch") {
                Picker(selection: $nonNotchMode) {
                    Text("Always show").tag(NonNotchMode.always)
                    Text("Show on hover").tag(NonNotchMode.hover)
                    Text("Hide").tag(NonNotchMode.hidden)
                } label: {
                    Text("Island")
                    Text("On a MacBook Air, iMac or external display the island can stay out of the way of the menu bar.")
                }
            }

            Section("Fit to notch") {
                LabeledContent {
                    SliderValue(value: $heightAdjust, range: -6...6, step: 0.5, unit: "pt", signed: true)
                } label: {
                    Text("Notification height")
                    Text("Fine-tune live notifications so they match the height of your notch exactly.")
                }

                HStack {
                    Spacer()
                    Button("Reset") { heightAdjust = 0 }
                    Button("Preview") {
                        NotificationCenter.default.post(name: .testChargingActivity, object: nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Вкладка «Media»: плеер

struct MediaSettings: View {
    @AppStorage("showMusicActivity") private var showActivity = true
    @AppStorage("showSkipButtons") private var showSkipButtons = false
    @AppStorage("playPauseAnimation") private var playPauseAnimation = 0.15
    @AppStorage("progressHoverAnimation") private var hoverAnimation = 0.12
    @AppStorage("artworkColors") private var artworkColors = true

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle(isOn: $showActivity) {
                    Text("Show track changes")
                    Text("Briefly show the artwork when a new track starts or playback resumes.")
                }
            }

            Section("Player") {
                Toggle(isOn: $showSkipButtons) {
                    Text("Show 15-second skip buttons")
                    Text("Useful for podcasts, audiobooks and videos.")
                }
            }

            Section("Appearance") {
                Toggle(isOn: $artworkColors) {
                    Text("Colors from artwork")
                    Text("Tint the equalizer, progress bar and buttons with the main color of the current artwork. When off, everything stays white.")
                }
            }

            Section("Animations") {
                LabeledContent {
                    SliderValue(value: $playPauseAnimation, range: 0...0.5, step: 0.05, unit: "s")
                } label: {
                    Text("Play/Pause icon")
                    Text("How quickly the play and pause icons switch. 0 turns the animation off.")
                }
                LabeledContent {
                    SliderValue(value: $hoverAnimation, range: 0...0.5, step: 0.02, unit: "s")
                } label: {
                    Text("Progress bar on hover")
                    Text("How quickly the progress bar thickens when you hover over it. 0 turns the animation off.")
                }
            }

            Section {
                Label("Works with Music, Spotify, browsers (YouTube) and most players that appear in Control Center.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Вкладка «Battery»

struct BatterySettings: View {
    @AppStorage("showChargingActivity") private var showCharging = true
    @AppStorage("colorfulBattery") private var colorful = false

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle(isOn: $showCharging) {
                    Text("Show charging animation")
                    Text("Show the battery level for a few seconds when you connect the charger.")
                }
                HStack {
                    Spacer()
                    Button("Preview") {
                        NotificationCenter.default.post(name: .testChargingActivity, object: nil)
                    }
                }
            }

            Section("Appearance") {
                Toggle(isOn: $colorful) {
                    Text("Colorful battery")
                    Text("Green when the charge is high, then yellow, orange and red as it drops. When off, the icon looks like the one in the macOS menu bar.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Вкладка «Devices»: наушники и Bluetooth

struct DevicesSettings: View {
    @AppStorage("showBluetoothActivity") private var showBluetooth = true
    @AppStorage("bluetoothHeadphonesOnly") private var headphonesOnly = true

    var body: some View {
        Form {
            Section("Bluetooth") {
                Toggle(isOn: $showBluetooth) {
                    Text("Show connected devices")
                    Text("Show the device icon and battery level when headphones connect.")
                }
                Toggle(isOn: $headphonesOnly) {
                    Text("Headphones only")
                    Text("When off, keyboards, mice and other Bluetooth devices are shown too.")
                }
                .disabled(!showBluetooth)
            }

            Section {
                Label("Battery level is available for AirPods and Beats. Other headphones are shown without it.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Вкладка «Clipboard»: история буфера обмена

struct ClipboardSettings: View {
    @AppStorage("clipboardHistory") private var enabled = true
    @AppStorage("clipboardLimit") private var limit = 30

    var body: some View {
        Form {
            Section("Clipboard history") {
                Toggle(isOn: $enabled) {
                    Text("Keep clipboard history")
                    Text("Remember the text and images you copy, so you can copy them again from the island.")
                }
                Picker(selection: $limit) {
                    ForEach([10, 30, 50, 100], id: \.self) { Text(verbatim: "\($0)").tag($0) }
                } label: {
                    Text("Items to keep")
                    Text("Pinned items are kept regardless of this limit.")
                }
                .disabled(!enabled)
            }

            Section {
                Label("Passwords copied from password managers are never saved. History is stored only on this Mac.",
                      systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Вкладка «HUD»: громкость и яркость

struct HUDSettings: View {
    @AppStorage("replaceSystemHUD") private var enabled = false
    @AppStorage("hudShowPercent") private var showPercent = true
    @State private var trusted = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Volume and brightness") {
                Toggle(isOn: $enabled) {
                    Text("Replace system HUD")
                    Text("Show volume and brightness changes in the island instead of the standard macOS indicator.")
                }
                Toggle(isOn: $showPercent) {
                    Text("Show percentage")
                    Text("Show the exact level next to the bar.")
                }
                .disabled(!enabled)
            }

            if enabled {
                Section("Permission") {
                    if trusted {
                        Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Accessibility access required", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("RequiemNotch needs it to catch the volume and brightness keys before macOS shows its own indicator.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("Grant Access") { HUDController.requestAccess() }
                        }
                    }
                }
            }

            Section {
                Label("Hold Option and Shift while pressing the keys for finer steps. Brightness works on the built-in display.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = AXIsProcessTrusted() }
    }
}

// MARK: - Вкладка «About»

struct AboutSettings: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(verbatim: "RequiemNotch")
                .font(.title.bold())
            Text("A Dynamic Island for your Mac.")
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("Version")
                Text(verbatim: version)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Link(destination: AppLinks.github) {
                    Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: AppLinks.feedback) {
                    Label("Send Feedback", systemImage: "bubble.left.and.text.bubble.right")
                }
            }
            .padding(.top, 6)

            Text("Made by requiem")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Ползунок со значением

struct SliderValue: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var signed = false

    var body: some View {
        HStack {
            Slider(value: $value, in: range, step: step)
                .frame(width: 160)
            Text(verbatim: String(format: signed ? "%+.1f %@" : "%.2f %@", value, unit))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}

// MARK: - Язык приложения

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, ru, uk

    var id: String { rawValue }

    /// Язык, с которым приложение запущено (запоминается один раз при старте)
    static let atLaunch: AppLanguage =
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system

    /// Названия языков пишем на самих языках — так их узнают в любом интерфейсе
    @ViewBuilder var label: some View {
        switch self {
        case .system: Text("System default")
        case .en: Text(verbatim: "English")
        case .ru: Text(verbatim: "Русский")
        case .uk: Text(verbatim: "Українська")
        }
    }

    /// Сохранить выбор: macOS применит его при следующем запуске
    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// Перезапустить приложение
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Автозапуск при входе в систему

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle(isOn: $enabled) {
            Text("Launch at login")
            Text("Start RequiemNotch automatically when you log in to your Mac.")
        }
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
                print("Launch at login: \(error)")
            }
        }
    }
}
