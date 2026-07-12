import AVFoundation

let devices = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.external, .builtInWideAngleCamera],
    mediaType: .video,
    position: .unspecified
).devices

for device in devices {
    if device.localizedName.lowercased().contains("insta360") {
        print("Device: \(device.localizedName)")
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let fps = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            
            let bytes: [UInt8] = [
                UInt8((subtype >> 24) & 0xff),
                UInt8((subtype >> 16) & 0xff),
                UInt8((subtype >> 8) & 0xff),
                UInt8(subtype & 0xff)
            ]
            let subtypeStr = String(bytes: bytes, encoding: .macOSRoman) ?? "\(subtype)"
            
            print(" - \(dimensions.width)x\(dimensions.height) \(subtypeStr) max_fps: \(fps)")
        }
    }
}
