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

    private let queue = DispatchQueue(label: "RequiemNotch.camera")
    private var configured = false

    /// Включить камеру (при первом разе macOS спросит разрешение)
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            status = .starting
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.run() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    /// Выключить камеру (зелёный огонёк гаснет)
    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
        if status == .running || status == .starting { status = .idle }
    }

    private func run() {
        status = .starting
        queue.async {
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
            DispatchQueue.main.async { self.status = .running }
        }
    }
}

// MARK: - Превью камеры (AppKit-слой внутри SwiftUI)

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        private let previewLayer = AVCaptureVideoPreviewLayer()

        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.08))

            switch camera.status {
            case .running:
                CameraPreview(session: camera.session)
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
        .frame(width: 260, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(NotchAnimation.content, value: camera.status)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}

// MARK: - Кнопка зеркала в шапке острова

struct MirrorButton: View {
    @EnvironmentObject var model: NotchModel
    @AppStorage("showMirrorButton") private var enabled = true

    var body: some View {
        if enabled {
            Button {
                withAnimation(NotchAnimation.content) { model.showMirror.toggle() }
            } label: {
                Image(systemName: model.showMirror ? "web.camera.fill" : "web.camera")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .foregroundStyle(model.showMirror ? Color.white : Color.secondary)
            .help("Mirror")
        }
    }
}
