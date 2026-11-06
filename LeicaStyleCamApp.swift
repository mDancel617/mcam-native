//
//  LeicaStyleCamApp.swift
//  LeicaStyleCam
//
//  A minimal, Leica-inspired manual camera for iPhone.
//  - Stripped-down shooting UI
//  - Full manual control (shutter / ISO / exposure / focus / white balance)
//  - RAW (DNG) + processed capture, with a filmic "look" baked into the processed file
//
//  This is original work. It does not copy Leica's trademarks, logos, or
//  proprietary profiles; it is a look *inspired* by the color characteristics
//  commonly associated with Leica (warm-neutral tone, filmic contrast,
//  restrained-but-rich color).
//

import SwiftUI

@main
struct LeicaStyleCamApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// Root gate: ask for camera + photo-library permission, then show the camera.
struct RootView: View {
    @StateObject private var camera = CameraViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch camera.authorization {
            case .authorized:
                CameraView(camera: camera)
            case .denied:
                PermissionDeniedView()
            case .undetermined:
                Color.black
                    .onAppear { camera.requestAuthorization() }
            }
        }
        .ignoresSafeArea()
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.none")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera access is off")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(.white)
            Text("Enable Camera and Photos access in Settings to use the camera.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 40)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(Capsule().fill(.white))
            .padding(.top, 8)
        }
    }
}
