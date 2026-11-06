//
//  CameraViewModel.swift
//  LeicaStyleCam
//
//  Bridges the AVFoundation controller to SwiftUI. Holds the manual-control
//  state, the current preview image, and capture status.
//

import SwiftUI
import AVFoundation
import CoreImage

enum CameraAuthorization { case undetermined, authorized, denied }

enum ExposureMode: String, CaseIterable, Identifiable {
    case auto = "A"          // program auto
    case manual = "M"        // full manual shutter + ISO
    var id: String { rawValue }
}

@MainActor
final class CameraViewModel: NSObject, ObservableObject {

    // Permissions
    @Published var authorization: CameraAuthorization = .undetermined

    // Live preview
    @Published var previewImage: CIImage?

    // Look
    @Published var look: LeicaLook = .classic {
        didSet { controller.currentLook = look }
    }

    // Capture mode
    @Published var rawEnabled: Bool = true {
        didSet { controller.rawEnabled = rawEnabled }
    }

    // Exposure
    @Published var exposureMode: ExposureMode = .auto { didSet { applyExposure() } }
    @Published var iso: Float = 100 { didSet { if exposureMode == .manual { applyExposure() } } }
    @Published var shutterSeconds: Double = 1.0 / 125.0 { didSet { if exposureMode == .manual { applyExposure() } } }
    @Published var exposureBias: Float = 0 { didSet { if exposureMode == .auto { controller.setExposureBias(exposureBias) } } }

    // Focus
    @Published var manualFocus: Bool = false { didSet { applyFocus() } }
    @Published var focusPosition: Float = 1.0 { didSet { if manualFocus { controller.setManualFocus(focusPosition) } } }

    // White balance
    @Published var manualWB: Bool = false { didSet { applyWB() } }
    @Published var wbKelvin: Float = 5600 { didSet { if manualWB { controller.setWhiteBalance(kelvin: wbKelvin, tint: wbTint) } } }
    @Published var wbTint: Float = 0 { didSet { if manualWB { controller.setWhiteBalance(kelvin: wbKelvin, tint: wbTint) } } }

    // Color tools + focus peaking (post-look)
    @Published var contrast: Float = 1.0 { didSet { controller.lookContrast = contrast } }
    @Published var saturation: Float = 1.0 { didSet { controller.lookSaturation = saturation } }
    @Published var soften: Float = 0.0 { didSet { controller.lookSoften = soften } }
    @Published var focusPeaking: Bool = false { didSet { controller.peakingEnabled = focusPeaking } }

    // Status
    @Published var isCapturing = false
    @Published var lastShotFlash = false
    @Published var statusMessage: String?

    // Device limits (for slider ranges)
    @Published var isoRange: ClosedRange<Float> = 50...3200
    @Published var shutterRange: ClosedRange<Double> = (1.0/8000.0)...(1.0/2.0)

    private let ciContext: CIContext
    private let controller: CameraController

    override init() {
        let ctx = CIContext(options: [.useSoftwareRenderer: false,
                                      .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) as Any])
        self.ciContext = ctx
        self.controller = CameraController(ciContext: ctx)
        super.init()
        controller.delegate = self
        controller.currentLook = look
        controller.rawEnabled = rawEnabled
    }

    var sharedContext: CIContext { ciContext }

    // MARK: Authorization

    func requestAuthorization() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorization = granted ? .authorized : .denied
                if granted { self.controller.configure() }
            }
        }
    }

    // MARK: Actions

    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        triggerShutterFlash()
        controller.capturePhoto()
    }

    func focusTap(at normalized: CGPoint) {
        controller.focus(at: normalized)
    }

    private func triggerShutterFlash() {
        lastShotFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.lastShotFlash = false
        }
    }

    // MARK: Apply control state

    private func applyExposure() {
        switch exposureMode {
        case .auto:
            controller.setAutoEverything()
            controller.setExposureBias(exposureBias)
            if manualFocus { controller.setManualFocus(focusPosition) }
            if manualWB { controller.setWhiteBalance(kelvin: wbKelvin, tint: wbTint) }
        case .manual:
            controller.setManualExposure(duration: shutterSeconds, iso: iso)
        }
    }

    private func applyFocus() {
        if manualFocus { controller.setManualFocus(focusPosition) }
        else { applyExposure() }
    }

    private func applyWB() {
        if manualWB { controller.setWhiteBalance(kelvin: wbKelvin, tint: wbTint) }
        else { applyExposure() }
    }

    private func status(_ s: String) {
        statusMessage = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.statusMessage == s { self?.statusMessage = nil }
        }
    }
}

// MARK: - CameraControllerDelegate

extension CameraViewModel: CameraControllerDelegate {
    nonisolated func cameraController(_ c: CameraController, didOutputPreview image: CIImage) {
        Task { @MainActor in self.previewImage = image }
    }

    nonisolated func cameraControllerDidUpdateLimits(_ c: CameraController) {
        Task { @MainActor in
            self.isoRange = c.minISO...max(c.maxISO, c.minISO + 1)
            let minS = CMTimeGetSeconds(c.minDuration)
            let maxS = CMTimeGetSeconds(c.maxDuration)
            if minS > 0, maxS > minS { self.shutterRange = minS...maxS }
        }
    }

    nonisolated func cameraController(_ c: CameraController, didCapture result: Result<CaptureResult, Error>) {
        Task { @MainActor in
            switch result {
            case .success(let shot):
                PhotoSaver.save(shot) { ok in
                    Task { @MainActor in
                        self.isCapturing = false
                        self.status(ok ? "Saved" : "Save failed")
                    }
                }
            case .failure(let err):
                self.isCapturing = false
                self.status(err.localizedDescription)
            }
        }
    }
}
