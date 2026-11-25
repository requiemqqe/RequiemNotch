import Foundation
import IOKit.ps
import Combine

/// Следит за батареей и сообщает о подключении зарядки
final class BatteryMonitor: ObservableObject {
    @Published private(set) var level: Int = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    /// Включён режим энергосбережения
    @Published private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Вызывается, когда подключили зарядку
    var onPluggedIn: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?

    init() {
        update(initial: true)

        // macOS сама дёргает этот колбэк при любом изменении питания
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.update(initial: false)
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }

        // Включили/выключили режим энергосбережения
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func update(initial: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        else { return }

        let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let wasPlugged = isPluggedIn

        level = max > 0 ? Int(Double(current) / Double(max) * 100) : current
        isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
        isPluggedIn = plugged

        if !initial && plugged && !wasPlugged {
            onPluggedIn?()
        }
    }
}

extension Notification.Name {
    /// Тестовая кнопка «Тест: зарядка» из меню
    static let testChargingActivity = Notification.Name("RequiemNotch.testChargingActivity")
}
