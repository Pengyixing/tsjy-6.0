import CoreMedia
import Foundation
import VideoToolbox

private final class FrameContext {
    let timestamp: TimeInterval

    init(timestamp: TimeInterval) {
        self.timestamp = timestamp
    }
}

final class H264VideoEncoder {
    var onEncodedFrame: ((EncodedVideoFrame) -> Void)?
    var onConfiguration: ((VideoConfiguration) -> Void)?

    private var compressionSession: VTCompressionSession?
    private var sequence: UInt64 = 0
    private var currentDimensions = CMVideoDimensions(width: 0, height: 0)
    private var latestParameterSignature = ""
    private var preferredQualityMode: VideoQualityMode = .fullHD

    private var targetFPS = 30
    private var targetBitrate = 12_000_000

    func setPreferredQualityMode(_ qualityMode: VideoQualityMode) {
        preferredQualityMode = qualityMode
    }

    func encode(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        encode(
            pixelBuffer: pixelBuffer,
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            duration: CMSampleBufferGetDuration(sampleBuffer),
            wallClockTimestamp: Date().timeIntervalSince1970
        )
    }

    func encode(
        pixelBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime,
        duration: CMTime,
        wallClockTimestamp: TimeInterval
    ) {
        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))

        if compressionSession == nil || width != currentDimensions.width || height != currentDimensions.height {
            recreateSession(width: width, height: height)
        }

        guard let compressionSession else { return }
        let context = Unmanaged.passRetained(FrameContext(timestamp: wallClockTimestamp))
        var flags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: context.toOpaque(),
            infoFlagsOut: &flags
        )
        if status != noErr {
            context.release()
        }
    }

    func stop() {
        if let compressionSession {
            VTCompressionSessionCompleteFrames(compressionSession, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(compressionSession)
        }
        compressionSession = nil
        latestParameterSignature = ""
        currentDimensions = CMVideoDimensions(width: 0, height: 0)
    }

    private func recreateSession(width: Int32, height: Int32) {
        stop()
        currentDimensions = CMVideoDimensions(width: width, height: height)
        updateEncodingTargets(width: Int(width), height: Int(height))

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else { return }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: targetFPS as CFTypeRef)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1 as CFTypeRef)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: targetFPS as CFTypeRef)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: targetBitrate as CFTypeRef)
        let dataRateLimits: [Int] = [targetBitrate * 2 / 8, 1]
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRateLimits as CFArray)
        VTCompressionSessionPrepareToEncodeFrames(session)
        compressionSession = session
    }

    private func updateEncodingTargets(width: Int, height: Int) {
        if let matchedMode = VideoQualityMode.matchingOutputDimensions(width: width, height: height) {
            targetFPS = matchedMode.targetFPS
            targetBitrate = matchedMode.targetBitrate
            return
        }

        targetFPS = preferredQualityMode.targetFPS
        targetBitrate = preferredQualityMode.targetBitrate
    }

    fileprivate func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer, wallClockTimestamp: TimeInterval) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }

        publishConfigurationIfNeeded(formatDescription)

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let payload = data(from: blockBuffer)
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyframe = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)

        sequence += 1
        onEncodedFrame?(
            EncodedVideoFrame(
                sequence: sequence,
                timestamp: wallClockTimestamp,
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                codec: "h264",
                isKeyframe: isKeyframe,
                payload: payload
            )
        )
    }

    private func publishConfigurationIfNeeded(_ formatDescription: CMFormatDescription) {
        var parameterSets: [String] = []
        var nalUnitHeaderLength: Int32 = 4
        var parameterCount = 0

        let countStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterCount,
            nalUnitHeaderLengthOut: &nalUnitHeaderLength
        )
        guard countStatus == noErr else { return }

        for index in 0..<parameterCount {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            var headerLength: Int32 = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: index,
                parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: &headerLength
            )
            guard status == noErr, let pointer else { continue }
            parameterSets.append(Data(bytes: pointer, count: size).base64EncodedString())
            nalUnitHeaderLength = headerLength
        }

        let signature = parameterSets.joined(separator: "|")
        guard !parameterSets.isEmpty, signature != latestParameterSignature else { return }
        latestParameterSignature = signature

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        onConfiguration?(
            VideoConfiguration(
                codec: "h264",
                width: Int(dimensions.width),
                height: Int(dimensions.height),
                targetFPS: targetFPS,
                bitrate: targetBitrate,
                nalUnitHeaderLength: Int(nalUnitHeaderLength),
                parameterSets: parameterSets,
                streamName: "Insta360 Panorama"
            )
        )
    }

    private func data(from blockBuffer: CMBlockBuffer) -> Data {
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
        }
        return data
    }
}

private let compressionOutputCallback: VTCompressionOutputCallback = { outputCallbackRefCon, sourceFrameRefCon, status, _, sampleBuffer in
    guard status == noErr,
          let outputCallbackRefCon,
          let sourceFrameRefCon,
          let sampleBuffer else {
        if let sourceFrameRefCon {
            Unmanaged<FrameContext>.fromOpaque(sourceFrameRefCon).release()
        }
        return
    }

    let encoder = Unmanaged<H264VideoEncoder>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
    let context = Unmanaged<FrameContext>.fromOpaque(sourceFrameRefCon).takeRetainedValue()
    encoder.handleEncodedSampleBuffer(sampleBuffer, wallClockTimestamp: context.timestamp)
}
