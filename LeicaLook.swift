//
//  LeicaLook.swift
//  LeicaStyleCam
//
//  The look engine. Each built-in look is a procedural 3D color cube (CIColorCube)
//  computed with the SAME math as the web version, so the two match. On top of the
//  look the engine applies global color tools (contrast, saturation), optional
//  de-sharpen softening, a look-strength blend, and — for the live preview only —
//  a focus-peaking overlay.
//
//  RAW files are always saved untouched; the look is baked only into the processed
//  (HEIC/JPEG) file and shown live.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum LeicaLook: String, CaseIterable, Identifiable {
    case classic, contemporary, monochrome, gold, chrome, portrait,
         cine, noir, faded, xpro, warm, log, infrared

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic";   case .contemporary: return "Contemp"
        case .monochrome: return "Mono";    case .gold: return "Gold"
        case .chrome: return "Chrome";      case .portrait: return "Portrait"
        case .cine: return "Cine";          case .noir: return "Noir"
        case .faded: return "Faded";        case .xpro: return "X-Pro"
        case .warm: return "Warm";          case .log: return "Log"
        case .infrared: return "Infrared"
        }
    }

    var shortLabel: String {
        switch self {
        case .classic: return "CLS";  case .contemporary: return "CNT"
        case .monochrome: return "BW"; case .gold: return "GLD"
        case .chrome: return "CHR";   case .portrait: return "POR"
        case .cine: return "CIN";     case .noir: return "NOR"
        case .faded: return "FAD";    case .xpro: return "XPR"
        case .warm: return "WRM";     case .log: return "LOG"
        case .infrared: return "IR"
        }
    }
}

/// Parameters for a standard (non-infrared) look — mirrors the web recipes.
private struct LookParams {
    var chMul: (Float, Float, Float) = (1, 1, 1)
    var toe: Float = 0.02
    var contrast: Float = 1.06
    var shoulder: Float = 0.10
    var sat: Float = 1.0
    var sh: (Float, Float, Float) = (0, 0, 0)
    var hi: (Float, Float, Float) = (0, 0, 0)
    var mono = false
    var mw: (Float, Float, Float) = (0.299, 0.587, 0.114)
}

final class LeicaLookProcessor {

    private let context: CIContext
    private var cubeCache: [LeicaLook: CIFilter] = [:]

    /// Look-strength 0...1, and post-look color tools.
    var intensity: Float = 1.0
    var contrast: Float = 1.0     // 0.5...1.8-ish (1 = neutral)
    var saturation: Float = 1.0   // 0...2 (1 = neutral)
    var soften: Float = 0.0       // 0...1 de-sharpen amount

    init(context: CIContext) { self.context = context }

    // MARK: - Public

    /// Apply the look + color tools to a frame (preview and capture).
    func apply(_ look: LeicaLook, to input: CIImage) -> CIImage {
        var img = input

        // de-sharpen / softening (before the look, like the web version)
        if soften > 0.001 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = img
            blur.radius = soften * 3.0
            if let blurred = blur.outputImage?.cropped(to: img.extent) {
                img = dissolve(img, blurred, t: soften * 0.6)
            }
        }

        // the look itself (procedural cube)
        var out = applyCube(img, for: look)

        // color tools: contrast + saturation
        let cc = CIFilter.colorControls()
        cc.inputImage = out
        cc.contrast = contrast
        cc.saturation = saturation
        cc.brightness = 0
        out = cc.outputImage ?? out

        // look strength
        return dissolve(img, out, t: intensity)
    }

    /// Focus-peaking overlay for the LIVE PREVIEW only (never baked into a photo).
    func peaking(on input: CIImage) -> CIImage {
        let edges = CIFilter.edges()
        edges.inputImage = input
        edges.intensity = 8.0
        guard let e = edges.outputImage else { return input }
        // threshold + tint the strong edges red, composite over the frame
        let mono = CIFilter.colorControls()
        mono.inputImage = e
        mono.saturation = 0
        mono.contrast = 6.0
        mono.brightness = -0.35
        guard let mask = mono.outputImage else { return input }
        let tint = CIFilter.colorMatrix()
        tint.inputImage = mask
        tint.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: 0.15, z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: 0.15, w: 0)
        tint.aVector = CIVector(x: 1, y: 1, z: 1, w: 0)   // alpha from edge strength
        guard let red = tint.outputImage?.cropped(to: input.extent) else { return input }
        let comp = CIFilter.sourceOverCompositing()
        comp.inputImage = red
        comp.backgroundImage = input
        return comp.outputImage ?? input
    }

    // MARK: - Cube

    private func applyCube(_ img: CIImage, for look: LeicaLook) -> CIImage {
        let filter: CIFilter
        if let cached = cubeCache[look] { filter = cached }
        else { filter = makeCube(for: look); cubeCache[look] = filter }
        filter.setValue(img, forKey: kCIInputImageKey)
        return filter.outputImage ?? img
    }

    private func clamp(_ x: Float) -> Float { min(max(x, 0), 1) }

    private func filmic(_ c: Float, _ toe: Float, _ con: Float, _ sho: Float) -> Float {
        var v = toe * (1 - c) + c
        v = (v - 0.5) * con + 0.5
        if v > 0 { v = v - powf(max(v, 0), 3) * sho }
        return clamp(v)
    }

    private func params(for look: LeicaLook) -> LookParams {
        var p = LookParams()
        switch look {
        case .classic:      p = LookParams(chMul:(1.03,1.00,0.97), toe:0.02, contrast:1.10, shoulder:0.10, sat:1.02, sh:(0,0.015,0.028), hi:(0.022,0.012,0))
        case .contemporary: p = LookParams(chMul:(1.00,1.00,1.02), toe:0.028, contrast:1.04, shoulder:0.10, sat:0.88, sh:(0.004,0.016,0.026), hi:(0.016,0.014,0.006))
        case .monochrome:   p = LookParams(toe:0.02, contrast:1.08, shoulder:0.09, sat:0, sh:(0,0.006,0.012), hi:(0.012,0.009,0), mono:true, mw:(0.299,0.587,0.114))
        case .gold:         p = LookParams(chMul:(1.05,1.01,0.95), toe:0.035, contrast:1.02, shoulder:0.12, sat:1.05, sh:(0.012,0.014,0), hi:(0.03,0.02,0))
        case .chrome:       p = LookParams(chMul:(1.02,1.02,1.00), toe:0.015, contrast:1.15, shoulder:0.07, sat:1.25, sh:(0,0.006,0.02), hi:(0.01,0.006,0))
        case .portrait:     p = LookParams(chMul:(1.02,1.00,1.00), toe:0.05, contrast:0.95, shoulder:0.14, sat:0.9, sh:(0.012,0.01,0.006), hi:(0.03,0.02,0.008))
        case .cine:         p = LookParams(chMul:(1.03,1.00,1.00), toe:0.03, contrast:1.06, shoulder:0.10, sat:0.95, sh:(0,0.02,0.035), hi:(0.04,0.022,0))
        case .noir:         p = LookParams(toe:0.0, contrast:1.30, shoulder:0.05, sat:0, sh:(0,0.004,0.01), hi:(0.02,0.014,0), mono:true, mw:(0.32,0.52,0.16))
        case .faded:        p = LookParams(chMul:(1.00,1.01,1.00), toe:0.095, contrast:0.90, shoulder:0.14, sat:0.80, sh:(0.022,0.030,0.028), hi:(0.020,0.018,0.016))
        case .xpro:         p = LookParams(chMul:(1.03,1.02,0.97), toe:0.01, contrast:1.22, shoulder:0.06, sat:1.20, sh:(0,0.030,0.045), hi:(0.055,0.040,0))
        case .warm:         p = LookParams(chMul:(1.045,1.00,0.955), toe:0.045, contrast:0.96, shoulder:0.14, sat:0.95, sh:(0.010,0.009,0.006), hi:(0.035,0.022,0))
        case .log:          p = LookParams(toe:0.16, contrast:0.68, shoulder:0.20, sat:0.70, sh:(0,0.004,0.006), hi:(0,0,0))
        case .infrared:     break // handled separately
        }
        return p
    }

    private func standardMap(_ r0: Float, _ g0: Float, _ b0: Float, _ p: LookParams) -> (Float, Float, Float) {
        var r = r0 * p.chMul.0, g = g0 * p.chMul.1, b = b0 * p.chMul.2
        if p.mono {
            let l = p.mw.0 * r + p.mw.1 * g + p.mw.2 * b
            r = l; g = l; b = l
        }
        r = filmic(r, p.toe, p.contrast, p.shoulder)
        g = filmic(g, p.toe, p.contrast, p.shoulder)
        b = filmic(b, p.toe, p.contrast, p.shoulder)
        let l = 0.2126 * r + 0.7152 * g + 0.0722 * b
        r = clamp(l + (r - l) * p.sat); g = clamp(l + (g - l) * p.sat); b = clamp(l + (b - l) * p.sat)
        r = clamp(r + p.sh.0 * (1 - l) + p.hi.0 * l)
        g = clamp(g + p.sh.1 * (1 - l) + p.hi.1 * l)
        b = clamp(b + p.sh.2 * (1 - l) + p.hi.2 * l)
        return (r, g, b)
    }

    // Infrared: foliage -> pink, sky -> teal, skin kept natural (same as web).
    private func infraredMap(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let (h, s, v) = rgb2hsv(r, g, b)
        let hue = h * 360
        func ss(_ a: Float, _ bb: Float, _ x: Float) -> Float {
            if bb == a { return 0 }
            let t = min(max((x - a) / (bb - a), 0), 1); return t * t * (3 - 2 * t)
        }
        let wf = max(0, (ss(55,82,hue) - ss(150,186,hue))) * ss(0.10,0.26,s)
        let wsky = max(0, (ss(186,205,hue) - ss(255,276,hue))) * ss(0.08,0.22,s)
        let fol = hsv2rgb(330.0/360.0, min(1, s*1.05+0.12), min(1, v*1.18+0.06))
        let sky = hsv2rgb(198.0/360.0, min(1, s*1.10), v*0.82)
        let wb = max(0, 1 - wf - wsky)
        var rr = r*wb + fol.0*wf + sky.0*wsky
        var gg = g*wb + fol.1*wf + sky.1*wsky
        var bb = b*wb + fol.2*wf + sky.2*wsky
        rr = clamp((rr-0.5)*1.12+0.5); gg = clamp((gg-0.5)*1.12+0.5); bb = clamp((bb-0.5)*1.12+0.5)
        return (rr, gg, bb)
    }

    private func makeCube(for look: LeicaLook) -> CIFilter {
        let size = 16
        var data = [Float](repeating: 0, count: size*size*size*4)
        let p = params(for: look)
        var off = 0
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let ri = Float(r)/Float(size-1), gi = Float(g)/Float(size-1), bi = Float(b)/Float(size-1)
                    let (R, G, B) = (look == .infrared) ? infraredMap(ri, gi, bi) : standardMap(ri, gi, bi, p)
                    data[off+0] = R; data[off+1] = G; data[off+2] = B; data[off+3] = 1
                    off += 4
                }
            }
        }
        let cubeData = data.withUnsafeBufferPointer { Data(buffer: $0) }
        let f = CIFilter(name: "CIColorCube")!
        f.setValue(size, forKey: "inputCubeDimension")
        f.setValue(cubeData, forKey: "inputCubeData")
        return f
    }

    // MARK: - helpers

    private func dissolve(_ a: CIImage, _ b: CIImage, t: Float) -> CIImage {
        if t >= 0.999 { return b }
        if t <= 0.001 { return a }
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = a
        mix.targetImage = b
        mix.time = t
        return mix.outputImage?.cropped(to: a.extent) ?? b
    }

    private func rgb2hsv(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let mx = max(r, max(g, b)), mn = min(r, min(g, b)), d = mx - mn
        var h: Float = 0
        if d != 0 {
            if mx == r { h = (g - b) / d; h = h.truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6; if h < 0 { h += 1 }
        }
        let s = mx == 0 ? 0 : d / mx
        return (h, s, mx)
    }

    private func hsv2rgb(_ h: Float, _ s: Float, _ v: Float) -> (Float, Float, Float) {
        let i = floor(h * 6)
        let f = h * 6 - i
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch Int(i) % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
