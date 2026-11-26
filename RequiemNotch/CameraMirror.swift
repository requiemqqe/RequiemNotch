import SwiftUI
import AppKit
import AVFoundation
import Combine

// MARK: - Камера для зеркала

final class CameraController: ObservableObject {
    static let shared = CameraController()

    enum Status: Equatable {
        case idle, starting, running, denied, unavailable
    }

    @Published private(set) var status: Status = .idle
    let session = AVCaptureSession()

    /// Один слой превью на всё приложение. Если создавать новый при каждом открытии
    /// зеркала, macOS со второго раза не может подключить его к камере
    /// (ошибка CMIOGraphConnectNodeInput) — и картинка остаётся чёрной
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    private let queue = DispatchQueue(label: "RequiemNotch.camera")
    private var configured = false
    /// Должна ли камера сейчас работать. Решает NotchWindowController:
    /// «остров раскрыт и выбрана вкладка зеркала»
    private var wanted = false

    /// Включить или выключить камеру. Можно вызывать сколько угодно раз подряд:
    /// команды выполняются строго по очереди, поэтому побеждает последняя
    func setActive(_ active: Bool) {
        guard active != wanted else { return }
        wanted = active
        active ? start() : apply(running: false)
    }

    /// Включить камеру (при первом разе macOS спросит разрешение)
    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            apply(running: true)
        case .notDetermined:
            status = .starting
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if !granted { self.status = .denied }
                    // Пока отвечали на запрос, остров могли свернуть — тогда не включаем
                    else if self.wanted { self.apply(running: true) }
                    else { self.status = .idle }
                }
            }
        default:
            status = .denied
        }
    }

    /// Запустить или остановить сессию камеры на её собственной очереди
    private func apply(running: Bool) {
        if running { status = .starting }
        queue.async {
            if running {
                if !self.configured {
                    guard let device = AVCaptureDevice.default(for: .video),
                          let input = try? AVCaptureDeviceInput(device: device),
                          self.session.canAddInput(input) else {
                        DispatchQueue.main.async { self.status = .unavailable }
                        return
                    }
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .medium
                    self.session.addInput(input)
                    self.session.commitConfiguration()
                    self.configured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
            } else if self.session.isRunning {
                // Зелёный огонёк камеры гаснет
                self.session.stopRunning()
            }

            let isRunning = self.session.isRunning
            DispatchQueue.main.async {
                guard self.status != .denied, self.status != .unavailable else { return }
                self.status = isRunning ? .running : .idle
            }
        }
    }
}

// MARK: - Превью камеры (общий слой, который переносится в окошко зеркала)

struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> PreviewView {
        PreviewView()
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    /// Окошко закрывается — отсоединяем общий слой
    static func dismantleNSView(_ nsView: PreviewView, coordinator: ()) {
        nsView.detach()
    }

    final class PreviewView: NSView {
        private var previewLayer: AVCaptureVideoPreviewLayer { CameraController.shared.previewLayer }

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { attach() } else { detach() }
        }

        /// Забрать общий слой себе (из прошлого окошка, если он там остался)
        private func attach() {
            guard previewLayer.superlayer !== layer else { return }
            previewLayer.removeFromSuperlayer()
            layer?.addSublayer(previewLayer)
            needsLayout = true
        }

        func detach() {
            if previewLayer.superlayer === layer { previewLayer.removeFromSuperlayer() }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

// MARK: - Зеркало в раскрытом острове (на месте полки)

struct MirrorView: View {
    @ObservedObject private var camera = CameraController.shared
    let height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.08))

            switch camera.status {
            case .running:
                CameraPreview()
                    // Как в зеркале — отражаем по горизонтали
                    .scaleEffect(x: -1, y: 1)
                    .transition(.opacity)

            case .denied:
                VStack(spacing: 6) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 18))
                    Text("Camera access denied")
                        .font(.caption)
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                }
                .foregroundStyle(.secondary)

            case .unavailable:
                VStack(spacing: 6) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 18))
                    Text("No camera found")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

            case .idle, .starting:
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: ShelfLayout.panelWidth, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(NotchAnimation.content, value: camera.status)
    }
}
