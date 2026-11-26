import SwiftUI
import AppKit

// MARK: - Окно приветствия
// Первый запуск — «Welcome». После обновления до новой версии (1.4 → 1.5) —
// один раз «What's New». Исправления (1.4 → 1.4.1) окно не показывают

enum WelcomeWindow {
    private static var window: NSWindow?
    private static let versionKey = "lastWelcomeVersion"
    /// Ключ из старых версий (до 1.5): «приветствие уже видели»
    private static let legacyKey = "hasSeenWelcome"

    /// Текущая версия без последней цифры исправления: "1.4.1" → "1.4"
    private static var currentVersion: String {
        let full = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return full.split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Показать при первом запуске или после обновления до новой версии
    static func showIfNeeded() {
        let defaults = UserDefaults.standard
        let lastSeen = defaults.string(forKey: versionKey)
        guard lastSeen != currentVersion else { return }

        // Ни разу не видел приветствие — это первый запуск
        let isFirstLaunch = lastSeen == nil && !defaults.bool(forKey: legacyKey)
        show(isUpdate: !isFirstLaunch)
    }

    /// Показать в любом случае (пункт «Welcome Guide» в меню)
    static func show(isUpdate: Bool = false) {
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
        UserDefaults.standard.set(true, forKey: legacyKey)

        window?.close()
        let hosting = NSHostingView(rootView: WelcomeView(isUpdate: isUpdate,
                                                          version: currentVersion) { close() })
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.contentView = hosting
        w.center()
        window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func close() {
        window?.close()
    }
}

// MARK: - Содержимое окна

struct WelcomeView: View {
    let isUpdate: Bool
    let version: String
    let onDone: () -> Void

    @State private var appeared = false

    private let features: [Feature] = [
        Feature(symbol: "cursorarrow.motionlines", color: .blue,
                title: "Hover over the notch",
                text: "Move the cursor to the notch and the island opens."),
        Feature(symbol: "play.circle.fill", color: .pink,
                title: "Control your music",
                text: "Music, Spotify, YouTube and more. Drag the progress bar to scrub."),
        Feature(symbol: "tray.full.fill", color: .orange,
                title: "Files shelf",
                text: "Drop files on the island and drag them out on any desktop."),
        Feature(symbol: "doc.on.clipboard.fill", color: .green,
                title: "Clipboard history",
                text: "Click to copy again, pin what matters. Passwords are never saved."),
        Feature(symbol: "web.camera.fill", color: .teal,
                title: "Mirror",
                text: "Check how you look before a call. The camera turns off when you leave."),
        Feature(symbol: "speaker.wave.2.fill", color: .purple,
                title: "Volume and brightness",
                text: "Sliders in the island. Turn on Settings → HUD for a new indicator."),
        Feature(symbol: "bolt.fill", color: .yellow,
                title: "Live notifications",
                text: "Charging, headphones and new tracks briefly appear in the notch."),
        Feature(symbol: "gearshape.fill", color: .gray,
                title: "Settings and updates",
                text: "Click the island icon in the menu bar. Updates install by themselves."),
    ]

    var body: some View {
        VStack(spacing: 24) {
            // Заголовок
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .scaleEffect(appeared ? 1 : 0.8)

                VStack(spacing: 4) {
                    if isUpdate {
                        Text("What's New in RequiemNotch \(version)")
                            .font(.title.bold())
                        Text("Here's everything the island can do now.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Welcome to RequiemNotch")
                            .font(.title.bold())
                        Text("Your notch is now a Dynamic Island.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Возможности: две колонки
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20, alignment: .top),
                                GridItem(.flexible(), spacing: 20, alignment: .top)],
                      spacing: 18) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    FeatureRow(feature: feature)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85)
                                    .delay(0.05 * Double(index)), value: appeared)
                }
            }

            Button(action: onDone) {
                Text(isUpdate ? "Continue" : "Get Started")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: 640)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

// MARK: - Одна возможность

private struct Feature {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey
}

private struct FeatureRow: View {
    let feature: Feature

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(feature.color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
