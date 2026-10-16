import AVFoundation
import AppKit
import SwiftUI

/// Takes a photo with the Mac's camera, an external webcam, or an iPhone used as a webcam.
struct CameraCaptureSheet: View {
    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Take a photo").font(.system(size: 18, weight: .semibold))
                Spacer()
                if camera.devices.count > 1 {
                    Picker("Camera", selection: Binding(get: { camera.selectedID ?? "" }, set: { camera.select($0) })) {
                        ForEach(camera.devices, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black)
                if let data = camera.captured, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    switch camera.status {
                    case .ready, .starting:
                        CameraPreview(session: camera.box.session)
                        if camera.status == .starting { ProgressView().controlSize(.small).tint(.white) }
                    case .denied:
                        message("BulkBoard doesn't have camera access.", action: "Open Privacy Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                        }
                    case .noCamera:
                        message("No camera found. Use the iPhone button or choose a photo instead.", action: nil, perform: nil)
                    case let .failed(text):
                        message(text, action: nil, perform: nil)
                    }
                }
            }
            .frame(width: 560, height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if let data = camera.captured {
                    Button("Retake") { camera.captured = nil }
                    Button("Use photo") {
                        onCapture(data)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button { camera.capture() } label: { Label("Take photo", systemImage: "camera.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(camera.status != .ready || camera.isCapturing)
                }
            }
            .controlSize(.regular)
        }
        .padding(20)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private func message(_ text: String, action: String?, perform: (() -> Void)?) -> some View {
        VStack(spacing: 10) {
            Text(text).foregroundStyle(.white).multilineTextAlignment(.center).frame(maxWidth: 360)
            if let action, let perform { Button(action, action: perform) }
        }
    }
}

@Observable
final class CameraController {
    enum Status: Equatable { case starting, ready, denied, noCamera, failed(String) }

    struct Device: Identifiable, Equatable {
        var id: String
        var name: String
    }

    private(set) var status: Status = .starting
    private(set) var devices: [Device] = []
    private(set) var selectedID: String?
    private(set) var isCapturing = false
    var captured: Data?
    let box = CaptureBox()

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { status = .denied; return }
        default:
            status = .denied
            return
        }
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
                                                         mediaType: .video, position: .unspecified)
        devices = discovery.devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
        guard let first = AVCaptureDevice.default(for: .video)?.uniqueID ?? devices.first?.id else {
            status = .noCamera
            return
        }
        select(first)
    }

    func select(_ id: String) {
        guard !id.isEmpty else { return }
        selectedID = id
        status = .starting
        box.configure(deviceID: id) { [weak self] ok in
            Task { @MainActor in self?.status = ok ? .ready : .failed("That camera couldn't start.") }
        }
    }

    func capture() {
        isCapturing = true
        box.capture { [weak self] data in
            Task { @MainActor in
                self?.isCapturing = false
                if let data { self?.captured = data } else { self?.status = .failed("The photo didn't come through. Try again.") }
            }
        }
    }

    func stop() { box.stop() }
}

/// Owns the capture session on its own queue, away from the main thread.
nonisolated final class CaptureBox: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.xmanxay.BulkBoard.camera")
    private var completion: (@Sendable (Data?) -> Void)?

    func configure(deviceID: String, done: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            guard let device = AVCaptureDevice(uniqueID: deviceID), let input = try? AVCaptureDeviceInput(device: device) else {
                return done(false)
            }
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.sessionPreset = .photo
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return done(false)
            }
            session.addInput(input)
            if session.outputs.isEmpty, session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
            done(session.isRunning)
        }
    }

    func capture(_ completion: @escaping @Sendable (Data?) -> Void) {
        queue.async { [self] in
            guard session.isRunning else { return completion(nil) }
            self.completion = completion
            output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [self] in
            completion?(data)
            completion = nil
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        view.layer = layer
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
