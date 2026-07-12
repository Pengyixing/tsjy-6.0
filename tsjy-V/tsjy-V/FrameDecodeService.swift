import CoreImage
import CoreMedia
import Foundation
import VideoToolbox

final class FrameDecodeService {
    struct DecodedFrame {
        let sequence: UInt64
        let frameTimestamp: TimeInterval
        let latency: TimeInterval
        let receiveTimestamp: TimeInterval
        let decodeFinishTimestamp: TimeInterval
        let size: CGSize
        let image: CGImage
    }

    var onDecodedFrame: ((DecodedFrame) -> Void)?
    var onFrameDropped: ((UInt64) -> Void)?

    private let queue = DispatchQueue(label: "tsjy.frame.decode", qos: .userInitiated)
    private let ciContext = CIContext()
    private var isDecoding = false
    private var pendingFrame: FrameSnapshot?
    private var currentConfiguration: VideoConfiguration?
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?

    func update(configuration: VideoConfiguration) {
        queue.async {
            self.currentConfiguration = configuration
            self.rebuildDecoder(configuration: configuration)
        }
    }

    func enqueue(frame: FrameSnapshot) {
        queue.async {
            if let pendingFrame = self.pendingFrame {
                self.onFrameDropped?(pendingFrame.sequence)
            }
            self.pendingFrame = frame
            guard !self.isDecoding else { return }
            self.processNext()
        }
    }

    private func processNext() {
        guard let frame = pendingFrame else { return }
        pendingFrame = nil
        isDecoding = true

        queue.async {
            defer {
                self.isDecoding = false
                if self.pendingFrame != nil {
                    self.processNext()
                }
            }

            let latency = Date().timeIntervalSince1970 - frame.timestamp
            if latency > 0.9, self.pendingFrame != nil {
                self.onFrameDropped?(frame.sequence)
                return
            }

            guard frame.codec == "h264",
                  let session = self.decompressionSession,
                  let formatDescription = self.formatDescription,
                  let sampleBuffer = self.makeSampleBuffer(from: frame, formatDescription: formatDescription) else {
                self.isDecoding = false
                if self.pendingFrame != nil {
                    self.processNext()
                }
                return
            }
            let decodeContext = Unmanaged.passRetained(DecodeContext(frame: frame, latency: latency))
            let status = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sampleBuffer,
                flags: [._EnableAsynchronousDecompression],
                frameRefcon: decodeContext.toOpaque(),
                infoFlagsOut: nil
            )
            if status != noErr {
                decodeContext.release()
                self.isDecoding = false
                if self.pendingFrame != nil {
                    self.processNext()
                }
            }
        }
    }

    private func rebuildDecoder(configuration: VideoConfiguration) {
        invalidateDecoder()
        guard configuration.codec == "h264",
              configuration.parameterSets.count >= 2,
              let sps = Data(base64Encoded: configuration.parameterSets[0]),
              let pps = Data(base64Encoded: configuration.parameterSets[1]) else {
            return
        }

        var formatDescription: CMFormatDescription?
        let status = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                let parameterSetPointers: [UnsafePointer<UInt8>] = [
                    spsBytes.bindMemory(to: UInt8.self).baseAddress!,
                    ppsBytes.bindMemory(to: UInt8.self).baseAddress!
                ]
                let parameterSetSizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: Int32(configuration.nalUnitHeaderLength),
                    formatDescriptionOut: &formatDescription
                )
            }
        }
        guard status == noErr, let formatDescription else {
            return
        }

        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let pixelBufferAttributes: [NSString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        var session: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: pixelBufferAttributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        guard sessionStatus == noErr else { return }
        self.formatDescription = formatDescription
        self.decompressionSession = session
    }

    private func invalidateDecoder() {
        if let decompressionSession {
            VTDecompressionSessionInvalidate(decompressionSession)
        }
        decompressionSession = nil
        formatDescription = nil
    }

    private func makeSampleBuffer(from frame: FrameSnapshot, formatDescription: CMVideoFormatDescription) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: frame.payload.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: frame.payload.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        let copyStatus = frame.payload.withUnsafeBytes { payloadBytes in
            guard let baseAddress = payloadBytes.baseAddress else { return kCMBlockBufferBadCustomBlockSourceErr }
            return CMBlockBufferReplaceDataBytes(with: baseAddress, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: frame.payload.count)
        }
        guard copyStatus == kCMBlockBufferNoErr else { return nil }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(max(currentConfiguration?.targetFPS ?? 20, 1))),
            presentationTimeStamp: CMTime(seconds: frame.timestamp, preferredTimescale: 1000),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = frame.payload.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        return sampleStatus == noErr ? sampleBuffer : nil
    }

    fileprivate func handleDecodedImageBuffer(_ imageBuffer: CVImageBuffer, context: DecodeContext) {
        guard let cgImage = ciContext.createCGImage(CIImage(cvPixelBuffer: imageBuffer), from: CGRect(origin: .zero, size: context.frame.size)) else {
            handleDecodeFailure()
            return
        }

        let decoded = DecodedFrame(
            sequence: context.frame.sequence,
            frameTimestamp: context.frame.timestamp,
            latency: context.latency,
            receiveTimestamp: context.frame.receiveTimestamp,
            decodeFinishTimestamp: Date().timeIntervalSince1970,
            size: context.frame.size,
            image: cgImage
        )
        DispatchQueue.main.async {
            self.onDecodedFrame?(decoded)
        }
        queue.async {
            self.isDecoding = false
            if self.pendingFrame != nil {
                self.processNext()
            }
        }
    }

    fileprivate func handleDecodeFailure() {
        queue.async {
            self.isDecoding = false
            if self.pendingFrame != nil {
                self.processNext()
            }
        }
    }
}

private final class DecodeContext {
    let frame: FrameSnapshot
    let latency: TimeInterval

    init(frame: FrameSnapshot, latency: TimeInterval) {
        self.frame = frame
        self.latency = latency
    }
}

private let decompressionOutputCallback: VTDecompressionOutputCallback = { decompressionOutputRefCon, sourceFrameRefCon, status, _, imageBuffer, _, _ in
    guard let sourceFrameRefCon else { return }
    let context = Unmanaged<DecodeContext>.fromOpaque(sourceFrameRefCon).takeRetainedValue()
    guard let decompressionOutputRefCon else { return }

    let decoder = Unmanaged<FrameDecodeService>.fromOpaque(decompressionOutputRefCon).takeUnretainedValue()
    guard status == noErr, let imageBuffer else {
        decoder.handleDecodeFailure()
        return
    }
    decoder.handleDecodedImageBuffer(imageBuffer, context: context)
}
