//
//  CameraController.swift
//  LeicaStyleCam
//
//  The AVFoundation capture engine: manual exposure / ISO / focus / white
//  balance, a live video feed for the processed preview, and RAW + processed
//  still capture.
//

import AVFoundation
import CoreImage
import UIKit

protocol CameraControllerDelegate: AnyObject {
    /// A new preview frame arrived (already a CIImage in sensor orientation).
    func cameraController(_ c: CameraController, didOutputPreview image: CIImage)
    /// Device limits changed (e.g. after switching lens) so UI can rescale.
    func cameraControllerDidUpdateLimits(_ c: CameraController)
    /// A capture finished (or failed).
    func cameraController(_ c: CameraController, didCapture result: Result<CaptureResult, Error>)
}

/// Bundles what a single shutter press produced.
struct CaptureResult {
    /// Untouched RAW (DNG) data, if RAW was enabled and supported.
    var rawData: Data?
    /// Processed full-resolution image with the look baked in (HEIC/JPEG).
    var processedData: Data?
}

enum CameraError: LocalizedError {
    case noDevice
    case configurationFailed
    case captureFailed(String)
    var errorDescription: String? {
        switch self {
        case .noDevice: return "No camera device is available."
        case .configurationFailed: return "Could not configure the camera."
        case .captureFailed(let m): return m
        }
    }
}

final class CameraController: NSObject {

    weak var delegate: CameraControllerDelegate?

    // MARK: Session
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let videoQueue = DispatchQueue(label: "camera.video.queue")

    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()

    // MARK: Look
    private let ciContext: CIContext
    private let look: LeicaLookProcessor

    /// Current look applied to preview + processed capture.
    var currentLook: LeicaLook = .classic
    /// Whether to also save an untouched RAW alongside the processed file.
    var rawEnabled: Bool = true
    /// Post-look color tools and preview-only focus peaking.
    var lookContrast: Float = 1.0
    var lookSaturation: Float = 1.0
    var lookSoften: Float = 0.0
    var peakingEnabled: Bool = false

    private func syncLookParams() {
        look.contrast = lookContrast
        look.saturation = lookSaturation
        look.soften = lookSoften
        look.intensity = 1.0
    }

    // Pending captures keyed by settings uniqueID.
    private var pendingRaw: Data?
    private var pendingProcessedSource: CIImage?
    private var inFlight = false

    // MARK: Device capability snapshot (read by the UI)
    private(set) var minISO: Float = 50
    private(set) var maxISO: Float = 3200
    private(set) var minDuration: CMTime = CMTime(value: 1, timescale: 8000)
    private(set) var maxDuration: CMTime = CMTime(value: 1, timescale: 4)

    init(ciContext: CIContext) {
        self.ciContext = ciContext
        self.look = LeicaLookProcessor(context: ciContext)
        super.init()
    }

    // MARK: - Setup

    func configure() {
        sessionQueue.async { [weak self] in
            self?.configureLocked()
        }
    }

    private func configureLocked() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Prefer the main wide camera; fall back sensibly.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video, position: .back)
        guard let dev = discovery.devices.first else {
            session.commitConfiguration()
            delegate?.cameraController(self, didCapture: .failure(CameraError.noDevice))
            return
        }
        device = dev

        do {
            let input = try AVCaptureDeviceInput(device: dev)
            self.input = input
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            session.commitConfiguration()
            delegate?.cameraController(self, didCapture: .failure(CameraError.configurationFailed))
            return
        }

        // Photo output (RAW capable).
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality

            // Full sensor resolution — up to 48MP on Pro devices (iOS 16+).
            if #available(iOS 16.0, *) {
                if let maxDim = dev.activeFormat.supportedMaxPhotoDimensions.last {
                    photoOutput.maxPhotoDimensions = maxDim
                }
            }
            // ProRAW (12-bit, full pipeline) where supported.
            if photoOutput.isAppleProRAWSupported {
                photoOutput.isAppleProRAWEnabled = true
            }
        }

        // Video output for the live, look-processed preview.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if let conn = videoOutput.connection(with: .video) {
            conn.videoOrientation = .portrait
        }

        session.commitConfiguration()

        captureLimits(from: dev)
        session.startRunning()
        delegate?.cameraControllerDidUpdateLimits(self)
    }

    private func captureLimits(from dev: AVCaptureDevice) {
        let f = dev.activeFormat
        minISO = f.minISO
        maxISO = f.maxISO
        minDuration = f.minExposureDuration
        maxDuration = f.maxExposureDuration
    }

    // MARK: - Manual controls

    /// Return to fully automatic exposure/focus/WB.
    func setAutoEverything() {
        configureDevice { dev in
            if dev.isExposureModeSupported(.continuousAutoExposure) {
                dev.exposureMode = .continuousAutoExposure
            }
            if dev.isFocusModeSupported(.continuousAutoFocus) {
                dev.focusMode = .continuousAutoFocus
            }
            if dev.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                dev.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        }
    }

    /// Manual exposure: shutter duration (seconds) and ISO.
    func setManualExposure(duration seconds: Double, iso: Float) {
        configureDevice { dev in
            let d = CMTime(seconds: seconds, preferredTimescale: 1_000_000_000)
            let clampedISO = min(max(iso, dev.activeFormat.minISO), dev.activeFormat.maxISO)
            let clampedD = CMTimeClamp(d, min: dev.activeFormat.minExposureDuration,
                                       max: dev.activeFormat.maxExposureDuration)
            dev.setExposureModeCustom(duration: clampedD, iso: clampedISO, completionHandler: nil)
        }
    }

    /// Exposure compensation in EV (works in auto mode).
    func setExposureBias(_ ev: Float) {
        configureDevice { dev in
            let clamped = min(max(ev, dev.minExposureTargetBias), dev.maxExposureTargetBias)
            dev.setExposureTargetBias(clamped, completionHandler: nil)
        }
    }

    /// Manual focus: 0.0 (near) ... 1.0 (infinity).
    func setManualFocus(_ lensPosition: Float) {
        configureDevice { dev in
            guard dev.isFocusModeSupported(.locked) else { return }
            dev.setFocusModeLockedWithLensPosition(min(max(lensPosition, 0), 1), completionHandler: nil)
        }
    }

    /// Tap-to-focus at a normalized point (0..1, 0..1).
    func focus(at point: CGPoint) {
        configureDevice { dev in
            if dev.isFocusPointOfInterestSupported {
                dev.focusPointOfInterest = point
                if dev.isFocusModeSupported(.autoFocus) { dev.focusMode = .autoFocus }
            }
            if dev.isExposurePointOfInterestSupported {
                dev.exposurePointOfInterest = point
                if dev.isExposureModeSupported(.autoExpose) { dev.exposureMode = .autoExpose }
            }
        }
    }

    /// Manual white balance by color temperature (Kelvin) and tint.
    func setWhiteBalance(kelvin: Float, tint: Float) {
        configureDevice { dev in
            guard dev.isWhiteBalanceModeSupported(.locked) else { return }
            let temp = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: kelvin, tint: tint)
            var g = dev.deviceWhiteBalanceGains(for: temp)
            let maxG = dev.maxWhiteBalanceGain
            g.redGain = min(max(g.redGain, 1), maxG)
            g.greenGain = min(max(g.greenGain, 1), maxG)
            g.blueGain = min(max(g.blueGain, 1), maxG)
            dev.setWhiteBalanceModeLocked(with: g, completionHandler: nil)
        }
    }

    private func configureDevice(_ work: (AVCaptureDevice) -> Void) {
        guard let dev = device else { return }
        sessionQueue.async {
            do {
                try dev.lockForConfiguration()
                work(dev)
                dev.unlockForConfiguration()
            } catch {
                // Ignore transient lock failures.
            }
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self, !self.inFlight else { return }
            self.inFlight = true
            self.pendingRaw = nil
            self.pendingProcessedSource = nil

            let settings: AVCapturePhotoSettings

            if self.rawEnabled {
                // Prefer a ProRAW (Bayer) format when enabled, else plain RAW.
                let rawType: OSType?
                if self.photoOutput.isAppleProRAWEnabled {
                    rawType = self.photoOutput.availableRawPhotoPixelFormatTypes.first {
                        AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
                    } ?? self.photoOutput.availableRawPhotoPixelFormatTypes.first
                } else {
                    rawType = self.photoOutput.availableRawPhotoPixelFormatTypes.first
                }
                if let rawType {
                    let processedFormat: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc]
                    settings = AVCapturePhotoSettings(rawPixelFormatType: rawType,
                                                      processedFormat: processedFormat)
                } else {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                }
            } else {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            settings.photoQualityPrioritization = .quality
            // Capture at the sensor's full resolution (up to 48MP on Pro devices).
            if #available(iOS 16.0, *) {
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

// MARK: - Live preview frames

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let base = CIImage(cvPixelBuffer: pb)
        syncLookParams()
        var processed = look.apply(currentLook, to: base)
        if peakingEnabled { processed = look.peaking(on: processed) }  // preview only
        delegate?.cameraController(self, didOutputPreview: processed)
    }
}

// MARK: - Still capture delegate

extension CameraController: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            finish(.failure(CameraError.captureFailed(error.localizedDescription)))
            return
        }
        if photo.isRawPhoto {
            // Keep RAW untouched.
            pendingRaw = photo.fileDataRepresentation()
        } else {
            // This is the processed source; we rebuild it with the look baked in.
            if let pb = photo.pixelBuffer {
                pendingProcessedSource = CIImage(cvPixelBuffer: pb)
            } else if let data = photo.fileDataRepresentation(),
                      let src = CIImage(data: data) {
                pendingProcessedSource = src
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        defer { inFlight = false }
        if let error {
            finish(.failure(CameraError.captureFailed(error.localizedDescription)))
            return
        }

        var processedData: Data?
        if let source = pendingProcessedSource {
            syncLookParams()  // peaking is never baked into the saved photo
            let graded = look.apply(currentLook, to: source)
            processedData = encodeHEIC(graded) ?? encodeJPEG(graded)
        }

        let result = CaptureResult(rawData: pendingRaw, processedData: processedData)
        finish(.success(result))
    }

    private func finish(_ r: Result<CaptureResult, Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraController(self, didCapture: r)
        }
    }

    // MARK: Encoders

    private func encodeHEIC(_ image: CIImage) -> Data? {
        let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        return ciContext.heifRepresentation(of: image,
                                            format: .RGBA8,
                                            colorSpace: space,
                                            options: [:])
    }

    private func encodeJPEG(_ image: CIImage) -> Data? {
        let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        return ciContext.jpegRepresentation(of: image,
                                            colorSpace: space,
                                            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95])
    }
}
