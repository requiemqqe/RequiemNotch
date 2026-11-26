import SwiftUI
import AppKit
import Combine
import CoreAudio
import AudioToolbox
import ApplicationServices

// MARK: - Что показывает HUD

enum HUDKind: Equatable {
    case volume
    case brightness
}

// MARK: - Свой HUD громкости и яркости вместо системного

final class HUDController: ObservableObject {
    @Published private(set) var kind: HUDKind = .volume
    /// Уровень 0…1
    @Published private(set) var level: Float = 0
    @Published private(set) var isMuted = false

    /// Вызывается, когда HUD нужно показать в острове
    var onShow: (() -> Void)?

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var listenedDevice: AudioDeviceID = 0
    private var isStarting = true

    /// Включено ли в настройках
    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "replaceSystemHUD") as? Bool ?? false
    }

    // MARK: Запуск

    func start() {
        // Слушаем громкость (ползунок в Пункте управления, другие приложения)
        attachVolumeListener()
        var defaultDevice = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &defaultDevice, nil, deviceListener)

        // Включили/выключили в настройках — пересобираем перехват клавиш
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateState() }

        updateState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isStarting = false
        }
    }

    /// Включить или выключить перехват клавиш по настройке и наличию разрешения
    private func updateState() {
        if isEnabled {
            if AXIsProcessTrusted() {
                startTap()
                permissionTimer?.invalidate()
                permissionTimer = nil
            } else if permissionTimer == nil {
                // Ждём, пока пользователь выдаст разрешение
                permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    if AXIsProcessTrusted() { self?.updateState() }
                }
            }
        } else {
            stopTap()
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    /// Запросить «Универсальный доступ» (системное окно + открыть настройки)
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Перехват клавиш

    private func startTap() {
        guard tap == nil else { return }
        // 14 — системные события (медиаклавиши), плюс обычные нажатия
        // (на некоторых клавиатурах яркость приходит как клавиши 144/145)
        let mask: CGEventMask = (1 << 14)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<HUDController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(nil, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        tapSource = source
    }

    private func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
    }

    private enum MediaKey: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    }

    /// Решаем, забрать нажатие себе (nil) или пропустить в систему
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // macOS иногда отключает перехват — включаем обратно
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        var key: MediaKey?
        var isDown = false

        if type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 {
            let code = (ns.data1 & 0xFFFF_0000) >> 16
            let state = (ns.data1 & 0xFF00) >> 8
            key = MediaKey(rawValue: code)
            isDown = state == 0x0A
        } else if type == .keyDown || type == .keyUp {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == 144 { key = .brightnessUp }
            if code == 145 { key = .brightnessDown }
            isDown = type == .keyDown
        }

        guard let key else { return pass }

        // Не умеем управлять этим устройством — пусть делает система
        switch key {
        case .soundUp, .soundDown, .mute:
            guard SystemVolume.canSet else { return pass }
        case .brightnessUp, .brightnessDown:
            guard DisplayBrightness.isAvailable else { return pass }
        }

        // ⌥ без ⇧ — системное сочетание (открыть настройки звука/дисплея)
        let flags = event.flags
        let option = flags.contains(.maskAlternate)
        let shift = flags.contains(.maskShift)
        if option && !shift { return pass }

        if isDown { perform(key, fine: option && shift) }
        return nil   // системный HUD не появится
    }

    private func perform(_ key: MediaKey, fine: Bool) {
        let steps: Float = fine ? 64 : 16

        func stepped(_ value: Float, up: Bool) -> Float {
            let next = (value * steps).rounded() + (up ? 1 : -1)
            return min(max(next / steps, 0), 1)
        }

        switch key {
        case .soundUp, .soundDown:
            let up = key == .soundUp
            let volume = stepped(SystemVolume.volume, up: up)
            if up || volume > 0 { SystemVolume.isMuted = false }
            SystemVolume.volume = volume
            show(.volume, level: volume, muted: SystemVolume.isMuted || volume == 0)

        case .mute:
            SystemVolume.isMuted.toggle()
            show(.volume, level: SystemVolume.volume, muted: SystemVolume.isMuted)

        case .brightnessUp, .brightnessDown:
            guard let current = DisplayBrightness.value else { return }
            let brightness = stepped(current, up: key == .brightnessUp)
            DisplayBrightness.value = brightness
            show(.brightness, level: brightness)
        }
    }

    private func show(_ kind: HUDKind, level: Float, muted: Bool = false) {
        self.kind = kind
        self.level = min(max(level, 0), 1)
        self.isMuted = muted
        onShow?()
    }

    // MARK: Громкость изменили не клавишами

    private lazy var volumeListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.systemVolumeChanged() }
    }

    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.attachVolumeListener() }
    }

    /// Подписаться на громкость текущего устройства вывода (и переподписаться при смене)
    private func attachVolumeListener() {
        if listenedDevice != 0 {
            var volume = SystemVolume.volumeAddress
            var mute = SystemVolume.muteAddress
            AudioObjectRemovePropertyListenerBlock(listenedDevice, &volume, nil, volumeListener)
            AudioObjectRemovePropertyListenerBlock(listenedDevice, &mute, nil, volumeListener)
        }
        listenedDevice = SystemVolume.device
        guard listenedDevice != 0 else { return }
        var volume = SystemVolume.volumeAddress
        var mute = SystemVolume.muteAddress
        AudioObjectAddPropertyListenerBlock(listenedDevice, &volume, nil, volumeListener)
        AudioObjectAddPropertyListenerBlock(listenedDevice, &mute, nil, volumeListener)
    }

    private func systemVolumeChanged() {
        guard isEnabled, !isStarting else { return }
        let volume = SystemVolume.volume
        show(.volume, level: volume, muted: SystemVolume.isMuted || volume == 0)
    }
}

// MARK: - Системная громкость (CoreAudio)

enum SystemVolume {
    static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Текущее устройство вывода звука
    static var device: AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    /// Можно ли менять громкость (у HDMI-мониторов и некоторых DAC нельзя)
    static var canSet: Bool {
        var address = volumeAddress
        var settable: DarwinBoolean = false
        let id = device
        return AudioObjectHasProperty(id, &address)
            && AudioObjectIsPropertySettable(id, &address, &settable) == noErr
            && settable.boolValue
    }

    static var volume: Float {
        get {
            var address = volumeAddress
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return value
        }
        set {
            var address = volumeAddress
            var value = Float32(newValue)
            AudioObjectSetPropertyData(device, &address, 0, nil,
                                       UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    static var isMuted: Bool {
        get {
            var address = muteAddress
            guard AudioObjectHasProperty(device, &address) else { return false }
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return value != 0
        }
        set {
            var address = muteAddress
            guard AudioObjectHasProperty(device, &address) else { return }
            var value: UInt32 = newValue ? 1 : 0
            AudioObjectSetPropertyData(device, &address, 0, nil,
                                       UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}

// MARK: - Яркость встроенного экрана (DisplayServices)

enum DisplayBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static let getFn: GetFn? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetFn.self)
    }()

    private static let setFn: SetFn? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: SetFn.self)
    }()

    /// Встроенный экран MacBook (или основной, если встроенного нет)
    private static var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static var isAvailable: Bool { setFn != nil && value != nil }

    static var value: Float? {
        get {
            guard let getFn else { return nil }
            var result: Float = 0
            return getFn(display, &result) == 0 ? result : nil
        }
        set {
            guard let newValue else { return }
            _ = setFn?(display, newValue)
        }
    }
}

// MARK: - HUD в острове: слева иконка, справа полоска

struct HUDCompactView: View {
    @EnvironmentObject var hud: HUDController
    @AppStorage("hudShowPercent") private var showPercent = true

    private var symbol: String {
        switch hud.kind {
        case .volume: return hud.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol,
                  variableValue: hud.kind == .volume && !hud.isMuted ? Double(hud.level) : nil)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24)
                .contentTransition(.symbolEffect(.replace))

            Spacer()

            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white)
                        .frame(width: 90 * CGFloat(hud.isMuted ? 0 : hud.level))
                }
                .frame(width: 90, height: 5)

                if showPercent {
                    Text(verbatim: "\(Int((hud.isMuted ? 0 : hud.level) * 100))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: 26, alignment: .trailing)
                        .contentTransition(.numericText())
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hud.level)
        .animation(.easeOut(duration: 0.15), value: hud.isMuted)
        .animation(.easeOut(duration: 0.15), value: hud.kind)
    }
}

