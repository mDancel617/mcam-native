//
//  PhotoSaver.swift
//  LeicaStyleCam
//
//  Saves a capture into the user's photo library: the processed (look-baked)
//  file as the primary asset, and the untouched RAW (DNG) as an alternate
//  resource on the same asset when present.
//

import Photos
import UIKit

enum PhotoSaver {

    static func save(_ result: CaptureResult, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()

                if let processed = result.processedData {
                    let opt = PHAssetResourceCreationOptions()
                    opt.uniformTypeIdentifier = UTTypeForData(processed)
                    request.addResource(with: .photo, data: processed, options: opt)
                }

                if let raw = result.rawData {
                    let opt = PHAssetResourceCreationOptions()
                    opt.uniformTypeIdentifier = "com.adobe.raw-image" // DNG
                    // If no processed photo existed, the RAW becomes the primary.
                    let type: PHAssetResourceType =
                        (result.processedData == nil) ? .photo : .alternatePhoto
                    request.addResource(with: type, data: raw, options: opt)
                }
            } completionHandler: { success, _ in
                DispatchQueue.main.async { completion(success) }
            }
        }
    }

    private static func UTTypeForData(_ data: Data) -> String {
        // Sniff HEIC vs JPEG by magic bytes; default to HEIC.
        if data.count > 12 {
            let bytes = [UInt8](data.prefix(12))
            // JPEG starts with FF D8 FF
            if bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
                return "public.jpeg"
            }
        }
        return "public.heic"
    }
}
