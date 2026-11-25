import SwiftUI
import AppKit

// MARK: - Окно приветствия (показывается один раз при первом запуске)

enum WelcomeWindow {
    private static var window: NSWindow?
    private static let seenKey = "hasSeenWelcome"

    /// Показать, если пользователь ещё не видел
    static func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return }
        show()
    }

    /// Показать в любом случае (пункт «Welcome Guide» в меню)
    static func show() {
        UserDefaults.standard.set(true, forKey: seenKey)

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hosting = NSHostingView(rootView: WelcomeView { close() })
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

// MARK: - Содержимое окна приветствия

struct WelcomeView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

            VStack(spacing: 6) {
                Text("Welcome to RequiemNotch")
                    .font(.title.bold())
                Text("Your notch is now a Dynamic Island.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(symbol: "cursorarrow.motionlines",
                           title: "Hover over the notch",
                           text: "Move the cursor to the notch to open the island.")
                FeatureRow(symbol: "play.circle.fill",
                           title: "Control your music",
                           text: "See what's playing in any app and control it right from the notch.")
                FeatureRow(symbol: "tray.and.arrow.down.fill",
                           title: "Keep files at hand",
                           text: "Drop files onto the island to carry them between desktops.")
                FeatureRow(symbol: "headphones",
                           title: "Charging and headphones",
                           text: "The island briefly shows when you plug in the charger or connect headphones.")
                FeatureRow(symbol: "capsule.fill",
                           title: "Settings in the menu bar",
                           text: "Click the capsule icon in the menu bar to open settings or quit.")
            }

            Button(action: onDone) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: 460)
    }
}

// MARK: - Строка с возможностью

private struct FeatureRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

