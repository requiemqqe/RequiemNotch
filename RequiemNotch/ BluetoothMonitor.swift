import SwiftUI
import AppKit
import Combine
import IOBluetooth

// MARK: - Подключённое Bluetooth-устройство

struct BluetoothAccessory: Equatable {
    let address: String
    let name: String
    let symbol: String
    var left: Int?
    var right: Int?
    var single: Int?
    var caseLevel: Int?

    /// Заряд для показа: общий, либо минимальный из двух наушников
    var level: Int? { single ?? [left, right].compactMap { $0 }.min() }
}

// MARK: - Слежение за подключением наушников и других устройств

final class BluetoothMonitor: NSObject, ObservableObject {
    /// Последнее подключённое устройство (nil — ничего не подключено)
    @Published private(set) var current: BluetoothAccessory?

    /// Вызывается, когда подключили устройство
    var onConnected: (() -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// Первые секунды после запуска macOS сообщает об уже подключённых устройствах —
    /// их запоминаем, но уведомление не показываем
    private var isStarting = true
    /// Обновление заряда раз в минуту, пока устройство подключено
    private var refreshTimer: Timer?

    func start() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isStarting = false
        }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification,
                                       device: IOBluetoothDevice) {
        guard shouldShow(device), let address = device.addressString else { return }

        // Следим за отключением этого устройства
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )

        let name = device.name ?? "Bluetooth"
        current = BluetoothAccessory(address: address, name: name,
                                     symbol: Self.symbol(for: device, name: name))
        if !isStarting { onConnected?() }

        // Заряд приходит не сразу после подключения — спрашиваем несколько раз
        for delay in [1.0, 4.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshBattery()
            }
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshBattery()
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification,
                                          device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        notification.unregister()
        disconnectNotifications[address] = nil
        if current?.address == address {
            refreshTimer?.invalidate()
            refreshTimer = nil
            withAnimation(NotchAnimation.content) { current = nil }
        }
    }

    // MARK: Заряд

    /// Берём заряд из системного отчёта Bluetooth — там же, откуда его показывает
    /// сама macOS в меню Bluetooth. Работает с любыми наушниками, которые сообщают заряд системе
    private func refreshBattery() {
        guard let device = current else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let levels = Self.readSystemReport(address: device.address, name: device.name)
            DispatchQueue.main.async {
                guard let self, var updated = self.current, updated.address == device.address,
                      let levels else { return }
                updated.single = levels.main
                updated.left = levels.left
                updated.right = levels.right
                updated.caseLevel = levels.caseLevel
                if updated != self.current {
                    withAnimation(NotchAnimation.content) { self.current = updated }
                }
            }
        }
    }

    private struct Levels {
        var main: Int?, left: Int?, right: Int?, caseLevel: Int?
    }

    /// Запускает `system_profiler SPBluetoothDataType -json` и ищет в нём наше устройство
    private static func readSystemReport(address: String, name: String) -> Levels? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return nil }

        // Адрес в отчёте записан как AA:BB:CC…, а в IOBluetooth — как aa-bb-cc…
        let wanted = address.uppercased().replacingOccurrences(of: "-", with: ":")

        for controller in controllers {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (deviceName, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let deviceAddress = (info["device_address"] as? String)?.uppercased()
                    guard deviceAddress == wanted || deviceName == name else { continue }

                    let levels = Levels(
                        main: percent(info["device_batteryLevelMain"]),
                        left: percent(info["device_batteryLevelLeft"]),
                        right: percent(info["device_batteryLevelRight"]),
                        caseLevel: percent(info["device_batteryLevelCase"])
                    )
                    return levels
                }
            }
        }
        return nil
    }

    /// "85%" → 85
    private static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String,
              let number = Int(text.filter(\.isNumber)),
              number > 0, number <= 100 else { return nil }
        return number
    }

    // MARK: Что показывать

    private func shouldShow(_ device: IOBluetoothDevice) -> Bool {
        let headphonesOnly = UserDefaults.standard.object(forKey: "bluetoothHeadphonesOnly") as? Bool ?? true
        guard headphonesOnly else { return true }
        let name = (device.name ?? "").lowercased()
        // 0x04 — класс «аудиоустройства» (наушники, колонки)
        return device.deviceClassMajor == 0x04
            || name.contains("airpods") || name.contains("beats") || name.contains("buds")
            || name.contains("headphone") || name.contains("headset")
    }

    /// Иконка по названию и типу устройства
    private static func symbol(for device: IOBluetoothDevice, name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("buds") { return "earbuds" }
        if n.contains("mouse") { return "magicmouse" }
        if n.contains("keyboard") { return "keyboard" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if n.contains("speaker") || n.contains("jbl") { return "hifispeaker" }
        if device.deviceClassMajor == 0x04 { return "headphones" }
        return "wave.3.right"
    }
}

// MARK: - Иконка устройства с кольцом заряда вокруг

struct DeviceBatteryRing: View {
    let symbol: String
    let level: Int?
    var size: CGFloat = 22
    var lineWidth: CGFloat = 2.2

    private var color: Color {
        guard let level else { return .white }
        return level <= 20 ? .red : .green
    }

    var body: some View {
        ZStack {
            // Фон кольца
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: lineWidth)
            // Заполненная часть = заряд
            if let level {
                Circle()
                    .trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: level)
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Мини-уведомление: слева иконка с кольцом, справа процент

struct BluetoothCompactView: View {
    @EnvironmentObject var bluetooth: BluetoothMonitor

    var body: some View {
        HStack {
            DeviceBatteryRing(symbol: bluetooth.current?.symbol ?? "headphones",
                              level: bluetooth.current?.level,
                              size: 22)
                .symbolEffect(.bounce, value: bluetooth.current?.address)
            Spacer()
            if let level = bluetooth.current?.level {
                Text("\(level)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(level <= 20 ? Color.red : Color.green)
                    .contentTransition(.numericText())
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .animation(NotchAnimation.content, value: bluetooth.current?.level)
    }
}

// MARK: - Значок устройства в шапке раскрытого острова

struct BluetoothBadge: View {
    @EnvironmentObject var bluetooth: BluetoothMonitor

    var body: some View {
        if let device = bluetooth.current {
            HStack(spacing: 5) {
                DeviceBatteryRing(symbol: device.symbol, level: device.level,
                                  size: 18, lineWidth: 1.8)
                if let level = device.level {
                    Text("\(level)%")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .help(device.name)
            .transition(.blurFade)
        }
    }
}
