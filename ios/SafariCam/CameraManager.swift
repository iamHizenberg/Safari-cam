import AVFoundation
import Photos
import CoreImage
import UIKit

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "safaricam.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var configured = false
    private let ciContext = CIContext()

    @Published var isRecording = false
    @Published var position: AVCaptureDevice.Position = .back
    @Published var beauty: Double = UserDefaults.standard.object(forKey: "beauty") as? Double ?? 0.35 {
        didSet { UserDefaults.standard.set(beauty, forKey: "beauty") }
    }

    // MARK: - Start

    func requestAndStart(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { video in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                guard video else { DispatchQueue.main.async { done(false) }; return }
                self.queue.async {
                    self.configure()
                    if !self.session.isRunning { self.session.startRunning() }
                    DispatchQueue.main.async { done(true) }
                }
            }
        }
    }

    private func configure() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        if let dev = camera(for: position), let inp = try? AVCaptureDeviceInput(device: dev), session.canAddInput(inp) {
            session.addInput(inp); videoInput = inp
        }
        if let mic = AVCaptureDevice.default(for: .audio), let inp = try? AVCaptureDeviceInput(device: mic), session.canAddInput(inp) {
            session.addInput(inp)
        }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.commitConfiguration()
        configured = true
    }

    private func camera(for pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos)
    }

    func flip() {
        guard !isRecording else { return }
        queue.async {
            let newPos: AVCaptureDevice.Position = self.position == .back ? .front : .back
            guard let dev = self.camera(for: newPos), let inp = try? AVCaptureDeviceInput(device: dev) else { return }
            self.session.beginConfiguration()
            if let old = self.videoInput { self.session.removeInput(old) }
            if self.session.canAddInput(inp) {
                self.session.addInput(inp); self.videoInput = inp
            } else if let old = self.videoInput {
                self.session.addInput(old)
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async { self.position = newPos }
        }
    }

    // MARK: - Video

    func startRecording() {
        queue.async {
            guard !self.movieOutput.isRecording else { return }
            if let conn = self.movieOutput.connection(with: .video) {
                if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = (self.position == .front) }
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("VID_\(Int(Date().timeIntervalSince1970)).mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecording = true }
        }
    }

    func stopRecording() {
        queue.async { if self.movieOutput.isRecording { self.movieOutput.stopRecording() } }
    }

    func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    // MARK: - Photo

    func capturePhoto() {
        queue.async {
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            if let conn = self.photoOutput.connection(with: .video) {
                if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = (self.position == .front) }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// 美白：明るさ↑ コントラスト↓ 彩度↓
    private func whiten(_ data: Data) -> Data {
        let a = beauty
        guard a > 0, let img = CIImage(data: data, options: [.applyOrientationProperty: true]),
              let f = CIFilter(name: "CIColorControls") else { return data }
        f.setValue(img, forKey: kCIInputImageKey)
        f.setValue(Float(0.12 * a), forKey: kCIInputBrightnessKey)
        f.setValue(Float(1.0 - 0.12 * a), forKey: kCIInputContrastKey)
        f.setValue(Float(1.0 - 0.18 * a), forKey: kCIInputSaturationKey)
        guard let out = f.outputImage, let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let jpg = ciContext.jpegRepresentation(of: out, colorSpace: cs, options: [:]) else { return data }
        return jpg
    }

    private func saveToPhotos(_ change: @escaping () -> Void, then: (() -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges(change) { _, _ in then?() }
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { self.isRecording = false }
        saveToPhotos({ PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) },
                     then: { try? FileManager.default.removeItem(at: url) })
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }
        let out = whiten(data)
        saveToPhotos({
            let r = PHAssetCreationRequest.forAsset()
            r.addResource(with: .photo, data: out, options: nil)
        })
    }
}
