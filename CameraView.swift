//
//  CameraView.swift
//  LeicaStyleCam
//
//  The shooting screen. Deliberately minimal: a clean full-bleed viewfinder,
//  a thin top status strip, a single row of manual readouts, a look selector,
//  and one shutter button. Everything else is a tap away, not on screen.
//

import SwiftUI

struct CameraView: View {
    @ObservedObject var camera: CameraViewModel
    @State private var activePanel: ControlPanel? = nil

    enum ControlPanel: String, Identifiable {
        case exposure, focus, whiteBalance, color
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Viewfinder
                CameraPreviewView(camera: camera)
                    .ignoresSafeArea()
                    .overlay(frameLines)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let n = CGPoint(x: location.x / geo.size.width,
                                        y: location.y / geo.size.height)
                        camera.focusTap(at: n)
                    }

                // Shutter flash
                if camera.lastShotFlash {
                    Color.black.ignoresSafeArea().transition(.opacity)
                }

                VStack(spacing: 0) {
                    topStrip
                    Spacer()
                    if let panel = activePanel {
                        controlPanel(panel)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    readoutRow
                    bottomBar
                }
                .padding(.vertical, 8)

                if let msg = camera.statusMessage {
                    Text(msg.uppercased())
                        .font(.system(size: 12, weight: .semibold).monospaced())
                        .tracking(2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(.bottom, 160)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: activePanel)
            .animation(.easeInOut(duration: 0.12), value: camera.lastShotFlash)
            .animation(.easeInOut(duration: 0.2), value: camera.statusMessage)
        }
    }

    // MARK: Top strip

    private var topStrip: some View {
        HStack {
            Text(camera.exposureMode == .manual ? "M" : "A")
                .font(.system(size: 13, weight: .bold).monospaced())
                .foregroundStyle(camera.exposureMode == .manual ? .yellow : .white)
                .frame(width: 22)

            Spacer()

            Button {
                camera.rawEnabled.toggle()
            } label: {
                Text(camera.rawEnabled ? "RAW+JPG" : "JPG")
                    .font(.system(size: 11, weight: .semibold).monospaced())
                    .tracking(1)
                    .foregroundStyle(camera.rawEnabled ? .yellow : .white.opacity(0.7))
            }

            Spacer()

            Button {
                camera.focusPeaking.toggle()
            } label: {
                Text("PEAK")
                    .font(.system(size: 11, weight: .semibold).monospaced())
                    .tracking(1)
                    .foregroundStyle(camera.focusPeaking ? .yellow : .white.opacity(0.7))
            }

            Spacer()

            Button { toggle(.color) } label: {
                Text("COLOR")
                    .font(.system(size: 11, weight: .semibold).monospaced())
                    .tracking(1)
                    .foregroundStyle(activePanel == .color ? .yellow : .white.opacity(0.7))
            }

            Spacer()

            Text(camera.look.shortLabel)
                .font(.system(size: 13, weight: .bold).monospaced())
                .foregroundStyle(.white)
                .frame(width: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 36)
    }

    // MARK: Frame lines (subtle Leica-ish bright-line feel)

    private var frameLines: some View {
        GeometryReader { g in
            let inset: CGFloat = 18
            Path { p in
                let r = CGRect(x: inset, y: inset,
                               width: g.size.width - inset * 2,
                               height: g.size.height - inset * 2)
                let c: CGFloat = 26
                // corner brackets only
                // top-left
                p.move(to: CGPoint(x: r.minX, y: r.minY + c)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + c, y: r.minY))
                // top-right
                p.move(to: CGPoint(x: r.maxX - c, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
                // bottom-left
                p.move(to: CGPoint(x: r.minX, y: r.maxY - c)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
                // bottom-right
                p.move(to: CGPoint(x: r.maxX - c, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    // MARK: Readout row (tap a value to open its control)

    private var readoutRow: some View {
        HStack(spacing: 0) {
            readout("SS", shutterText) { toggle(.exposure) }
            divider
            readout("ISO", isoText) { toggle(.exposure) }
            divider
            readout(camera.exposureMode == .auto ? "EV" : "F", evOrFocusText) {
                toggle(camera.exposureMode == .auto ? .exposure : .focus)
            }
            divider
            readout("WB", wbText) { toggle(.whiteBalance) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.35))
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 26)
    }

    private func readout(_ label: String, _ value: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold).monospaced())
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 15, weight: .semibold).monospaced())
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Bottom bar — look dial + shutter

    private var bottomBar: some View {
        HStack {
            // Exposure mode toggle
            Button {
                camera.exposureMode = (camera.exposureMode == .auto) ? .manual : .auto
            } label: {
                Text(camera.exposureMode.rawValue)
                    .font(.system(size: 18, weight: .bold).monospaced())
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().stroke(.white.opacity(0.4), lineWidth: 1.5))
            }

            Spacer()

            // Shutter
            Button {
                camera.capture()
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 3).frame(width: 74, height: 74)
                    Circle().fill(.white).frame(width: 60, height: 60)
                        .scaleEffect(camera.isCapturing ? 0.85 : 1)
                }
            }
            .disabled(camera.isCapturing)
            .animation(.easeInOut(duration: 0.1), value: camera.isCapturing)

            Spacer()

            // Look cycle
            Button {
                cycleLook()
            } label: {
                Text(camera.look.shortLabel)
                    .font(.system(size: 14, weight: .bold).monospaced())
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.white))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }

    // MARK: Control panels

    @ViewBuilder
    private func controlPanel(_ panel: ControlPanel) -> some View {
        VStack(spacing: 14) {
            switch panel {
            case .exposure:
                if camera.exposureMode == .manual {
                    labeledSlider("SHUTTER", shutterText,
                                  value: shutterBinding,
                                  range: 0...1)
                    labeledSlider("ISO", isoText,
                                  value: isoBinding,
                                  range: 0...1)
                } else {
                    labeledSlider("EXPOSURE", evOrFocusText,
                                  value: Binding(get: { Double(camera.exposureBias) },
                                                 set: { camera.exposureBias = Float($0) }),
                                  range: -3...3)
                }
            case .focus:
                Toggle("Manual focus", isOn: $camera.manualFocus)
                    .toggleStyle(.switch).tint(.yellow)
                    .font(.system(size: 13, weight: .semibold).monospaced())
                    .foregroundStyle(.white)
                if camera.manualFocus {
                    labeledSlider("FOCUS", focusText,
                                  value: Binding(get: { Double(camera.focusPosition) },
                                                 set: { camera.focusPosition = Float($0) }),
                                  range: 0...1)
                }
            case .whiteBalance:
                Toggle("Manual white balance", isOn: $camera.manualWB)
                    .toggleStyle(.switch).tint(.yellow)
                    .font(.system(size: 13, weight: .semibold).monospaced())
                    .foregroundStyle(.white)
                if camera.manualWB {
                    labeledSlider("TEMP", "\(Int(camera.wbKelvin))K",
                                  value: Binding(get: { Double(camera.wbKelvin) },
                                                 set: { camera.wbKelvin = Float($0) }),
                                  range: 2500...9000)
                    labeledSlider("TINT", String(format: "%+.0f", camera.wbTint),
                                  value: Binding(get: { Double(camera.wbTint) },
                                                 set: { camera.wbTint = Float($0) }),
                                  range: -50...50)
                }
            case .color:
                labeledSlider("CONTRAST", String(format: "%.2f", camera.contrast),
                              value: Binding(get: { Double(camera.contrast) },
                                             set: { camera.contrast = Float($0) }),
                              range: 0.6...1.6)
                labeledSlider("SATURATION", String(format: "%.2f", camera.saturation),
                              value: Binding(get: { Double(camera.saturation) },
                                             set: { camera.saturation = Float($0) }),
                              range: 0.0...2.0)
                labeledSlider("SOFTEN", "\(Int(camera.soften * 100))%",
                              value: Binding(get: { Double(camera.soften) },
                                             set: { camera.soften = Float($0) }),
                              range: 0.0...1.0)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.6)))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func labeledSlider(_ label: String, _ value: String,
                               value binding: Binding<Double>,
                               range: ClosedRange<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.system(size: 10, weight: .semibold).monospaced())
                    .tracking(1.5).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(value).font(.system(size: 13, weight: .semibold).monospaced())
                    .foregroundStyle(.yellow)
            }
            Slider(value: binding, in: range).tint(.white)
        }
    }

    // MARK: Helpers

    private func toggle(_ p: ControlPanel) {
        activePanel = (activePanel == p) ? nil : p
    }

    private func cycleLook() {
        let all = LeicaLook.allCases
        if let i = all.firstIndex(of: camera.look) {
            camera.look = all[(i + 1) % all.count]
        }
    }

    // Shutter slider maps 0...1 across a photographic range logarithmically.
    private var shutterBinding: Binding<Double> {
        Binding(
            get: {
                let r = camera.shutterRange
                let logMin = log(r.lowerBound), logMax = log(r.upperBound)
                return (log(camera.shutterSeconds) - logMin) / (logMax - logMin)
            },
            set: { t in
                let r = camera.shutterRange
                let logMin = log(r.lowerBound), logMax = log(r.upperBound)
                camera.shutterSeconds = exp(logMin + t * (logMax - logMin))
            })
    }

    private var isoBinding: Binding<Double> {
        Binding(
            get: {
                let r = camera.isoRange
                return Double((camera.iso - r.lowerBound) / (r.upperBound - r.lowerBound))
            },
            set: { t in
                let r = camera.isoRange
                camera.iso = r.lowerBound + Float(t) * (r.upperBound - r.lowerBound)
            })
    }

    // MARK: Text formatting

    private var shutterText: String {
        let s = camera.shutterSeconds
        if s >= 1 { return String(format: "%.0f\"", s) }
        return "1/\(Int((1.0 / s).rounded()))"
    }
    private var isoText: String { "\(Int(camera.iso.rounded()))" }
    private var focusText: String {
        camera.focusPosition >= 0.99 ? "∞" : String(format: "%.2f", camera.focusPosition)
    }
    private var evOrFocusText: String {
        camera.exposureMode == .auto
            ? String(format: "%+.1f", camera.exposureBias)
            : (camera.manualFocus ? focusText : "AF")
    }
    private var wbText: String {
        camera.manualWB ? "\(Int(camera.wbKelvin))K" : "AUTO"
    }
}
