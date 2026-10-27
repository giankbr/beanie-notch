import AVFoundation
import SwiftUI

// A mirror before a call: the camera runs only while this view is on screen.
struct CameraMirror: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreview {
        let view = CameraPreview()
        view.start()
        return view
    }

    func updateNSView(_ view: CameraPreview, context: Context) {}

    static func dismantleNSView(_ view: CameraPreview, coordinator: ()) {
        view.stop()
    }
}

final class CameraPreview: NSView {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "beanotch.camera")
    private let preview: AVCaptureVideoPreviewLayer

    override init(frame: NSRect) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frame)
        preview.videoGravity = .resizeAspectFill
        layer = preview
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [session, queue, preview] granted in
            guard granted else { return }
            queue.async {
                guard session.inputs.isEmpty,
                      let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else { return }
                session.addInput(input)
                session.startRunning()
                DispatchQueue.main.async {
                    if let connection = preview.connection, connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = true
                    }
                }
            }
        }
    }

    func stop() {
        queue.async { [session] in session.stopRunning() }
    }
}
