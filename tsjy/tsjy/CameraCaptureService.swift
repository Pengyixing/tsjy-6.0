import AVFoundation
import CoreImage
import CoreGraphics
import CoreMedia
import CoreVideo
import CoreVideo.CVPixelBuffer
import ImageIO
import UniformTypeIdentifiers

struct VideoRecordingState {
    var directoryURL: URL
    var currentFileURL: URL?
    var lastCompletedFileURL: URL?
    var isRecording: Bool
    var statusText: String
}

final class PanoramaVideoRecorder {
    private let fileManager: FileManager
    private let renderContext = CIContext()
    private let queue = DispatchQueue(label: "tsjy.video.recording")
    private var outputDirectory: URL
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var armedOutputURL: URL?
    private var lastCompletedFileURL: URL?
    private var isRecordingArmed = false
    private var hasWrittenFrames = false

    init(outputDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.outputDirectory = outputDirectory ?? Self.defaultRecordingDirectoryURL(fileManager: fileManager)
        try? fileManager.createDirectory(at: self.outputDirectory, withIntermediateDirectories: true)
    }

    var outputDirectoryURL: URL {
        queue.sync { outputDirectory }
    }

    var currentOutputURL: URL? {
        queue.sync { armedOutputURL }
    }

    var latestCompletedOutputURL: URL? {
        queue.sync { lastCompletedFileURL }
    }

    var isRecording: Bool {
        queue.sync { isRecordingArmed || writer != nil }
    }

    func startRecording(filePrefix: String = "panorama-recording") throws -> URL {
        try queue.sync {
            guard !isRecordingArmed, writer == nil else {
                throw NSError(
                    domain: "tsjy.recorder",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "录像已在进行中"]
                )
            }
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let timestamp = Self.fileTimestampFormatter.string(from: Date())
            let filename = "\(filePrefix)_\(timestamp).mp4"
            let fileURL = outputDirectory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            armedOutputURL = fileURL
            isRecordingArmed = true
            hasWrittenFrames = false
            return fileURL
        }
    }

    func append(pixelBuffer: CVPixelBuffer, at presentationTimeStamp: CMTime) throws {
        try queue.sync {
            guard isRecordingArmed || writer != nil else { return }
            if writer == nil {
                try prepareWriterIfNeeded(firstPixelBuffer: pixelBuffer)
            }
            guard let writer, let writerInput, let pixelBufferAdaptor else { return }
            guard writer.status != .failed else {
                throw writer.error ?? NSError(
                    domain: "tsjy.recorder",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "录像写入失败"]
                )
            }
            if writer.status == .unknown {
                writer.startWriting()
                writer.startSession(atSourceTime: presentationTimeStamp)
            }
            guard writerInput.isReadyForMoreMediaData else { return }
            guard let recordingBuffer = makeRecordingPixelBuffer(from: pixelBuffer, adaptor: pixelBufferAdaptor) else {
                throw NSError(
                    domain: "tsjy.recorder",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "无法创建录像缓冲区"]
                )
            }
            if pixelBufferAdaptor.append(recordingBuffer, withPresentationTime: presentationTimeStamp) {
                hasWrittenFrames = true
            } else {
                throw writer.error ?? NSError(
                    domain: "tsjy.recorder",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "无法写入录像帧"]
                )
            }
        }
    }

    func stopRecording() async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            var finishWriter: AVAssetWriter?
            var finishInput: AVAssetWriterInput?
            var outputURL: URL?
            var shouldDeleteArmedFile = false

            queue.sync {
                outputURL = armedOutputURL
                guard isRecordingArmed || writer != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                isRecordingArmed = false
                if !hasWrittenFrames || writer == nil {
                    shouldDeleteArmedFile = true
                    armedOutputURL = nil
                    writer = nil
                    writerInput = nil
                    pixelBufferAdaptor = nil
                    continuation.resume(returning: nil)
                    return
                }
                finishWriter = writer
                finishInput = writerInput
                writer = nil
                writerInput = nil
                pixelBufferAdaptor = nil
            }

            if shouldDeleteArmedFile, let outputURL, self.fileManager.fileExists(atPath: outputURL.path) {
                try? self.fileManager.removeItem(at: outputURL)
                return
            }

            guard let finishWriter, let finishInput, let outputURL else {
                return
            }

            finishInput.markAsFinished()
            finishWriter.finishWriting {
                self.queue.async {
                    let status = finishWriter.status
                    let error = finishWriter.error
                    self.armedOutputURL = nil
                    if status == .completed {
                        self.lastCompletedFileURL = outputURL
                        continuation.resume(returning: outputURL)
                    } else {
                        if self.fileManager.fileExists(atPath: outputURL.path) {
                            try? self.fileManager.removeItem(at: outputURL)
                        }
                        continuation.resume(throwing: error ?? NSError(
                            domain: "tsjy.recorder",
                            code: 5,
                            userInfo: [NSLocalizedDescriptionKey: "结束录像失败"]
                        ))
                    }
                }
            }
        }
    }

    private func prepareWriterIfNeeded(firstPixelBuffer: CVPixelBuffer) throws {
        guard let outputURL = armedOutputURL else {
            throw NSError(
                domain: "tsjy.recorder",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "未设置录像输出路径"]
            )
        }
        let width = CVPixelBufferGetWidth(firstPixelBuffer)
        let height = CVPixelBufferGetHeight(firstPixelBuffer)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(width * height * 8, 8_000_000),
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw NSError(
                domain: "tsjy.recorder",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "录像输入通道不可用"]
            )
        }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        self.writer = writer
        self.writerInput = input
        self.pixelBufferAdaptor = adaptor
    }

    private func makeRecordingPixelBuffer(
        from sourceBuffer: CVPixelBuffer,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> CVPixelBuffer? {
        var targetBuffer: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &targetBuffer)
            guard status == kCVReturnSuccess else { return nil }
        } else {
            let width = CVPixelBufferGetWidth(sourceBuffer)
            let height = CVPixelBufferGetHeight(sourceBuffer)
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                [
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ] as CFDictionary,
                &targetBuffer
            )
            guard status == kCVReturnSuccess else { return nil }
        }
        guard let targetBuffer else { return nil }
        renderContext.render(CIImage(cvPixelBuffer: sourceBuffer), to: targetBuffer)
        return targetBuffer
    }

    private static func defaultRecordingDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("tsjy/video-recordings", isDirectory: true)
    }

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}

final class CameraCaptureService: NSObject {
    var onEncodedFrame: ((EncodedVideoFrame) -> Void)?
    var onVideoConfiguration: ((VideoConfiguration) -> Void)?
    var onDevicesChanged: (([CameraDeviceInfo]) -> Void)?
    var onStatus: ((String) -> Void)?
    var onPreviewFrames: ((CGImage?, CGImage?) -> Void)?
    var onRecordingStateChanged: ((VideoRecordingState) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "tsjy.camera.capture")
    private let ffmpegQueue = DispatchQueue(label: "tsjy.camera.ffmpeg")
    private let preferredCaptureFPS = 30.0
    private var configuredDeviceID: String?
    private var latestDevices: [CameraDeviceInfo] = []
    private var lastEmission: CFTimeInterval = 0
    private let frameInterval: CFTimeInterval = 1.0 / 30.0
    private let encoder = H264VideoEncoder()
    private var lastPreviewEmission: CFTimeInterval = 0
    private let previewInterval: CFTimeInterval = 1.0 / 4.0
    private let ffmpegPreviewInterval: CFTimeInterval = 1.0 / 6.0
    private let context = CIContext()
    private var savedDebugFrameCount = 0
    private let debugFramesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("tsjy-raw-frames", isDirectory: true)
    private var preferredOutputPixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    private var loggedFirstCaptureFrame = false
    private let inputPriorityPreset = AVCaptureSession.Preset(rawValue: "AVCaptureSessionPresetInputPriority")
    private var ffmpegProcess: Process?
    private var ffmpegFrameIndex: Int64 = 0
    private var currentCaptureMode = "AVCapture"
    private var ffmpegPixelBufferPool: CVPixelBufferPool?
    private var ffmpegOutputHandle: FileHandle?
    private var ffmpegErrorHandle: FileHandle?
    private var selectedQualityMode: VideoQualityMode = .fullHD
    private let recorder = PanoramaVideoRecorder()
    private var recordingStatusText = "未录制"

    override init() {
        super.init()
        encoder.onEncodedFrame = { [weak self] frame in
            self?.onEncodedFrame?(frame)
        }
        encoder.onConfiguration = { [weak self] configuration in
            self?.onVideoConfiguration?(configuration)
        }
        publishRecordingState()
    }

    var recordingState: VideoRecordingState {
        VideoRecordingState(
            directoryURL: recorder.outputDirectoryURL,
            currentFileURL: recorder.currentOutputURL,
            lastCompletedFileURL: recorder.latestCompletedOutputURL,
            isRecording: recorder.isRecording,
            statusText: recordingStatusText
        )
    }

    func startRecording() throws -> URL {
        let fileURL = try recorder.startRecording(filePrefix: "panorama-recording")
        recordingStatusText = "录制中"
        publishRecordingState()
        return fileURL
    }

    func stopRecording() async throws -> URL? {
        let fileURL = try await recorder.stopRecording()
        if let fileURL {
            recordingStatusText = "已结束: \(fileURL.lastPathComponent)"
        } else {
            recordingStatusText = "已停止，未写入视频帧"
        }
        publishRecordingState()
        return fileURL
    }

    private func publishRecordingState() {
        DispatchQueue.main.async {
            self.onRecordingStateChanged?(self.recordingState)
        }
    }

    func refreshDevices() async throws -> [CameraDeviceInfo] {
        let authorized = await requestAccessIfNeeded()
        guard authorized else {
            throw NSError(domain: "tsjy.camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "未授予摄像头权限"])
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        let devices = discovery.devices.map { CameraDeviceInfo(id: $0.uniqueID, name: $0.localizedName) }
        latestDevices = devices.sorted { lhs, rhs in
            if lhs.name.localizedCaseInsensitiveContains("insta360") { return true }
            if rhs.name.localizedCaseInsensitiveContains("insta360") { return false }
            return lhs.name < rhs.name
        }
        onDevicesChanged?(latestDevices)
        return latestDevices
    }

    func supportedFormats(deviceID: String?) -> [CameraFormatInfo] {
        guard let device = resolveDevice(deviceID: deviceID) else { return [] }
        return device.formats
            .map {
                let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let subtype = CMFormatDescriptionGetMediaSubType($0.formatDescription)
                let maxFPS = $0.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                return CameraFormatInfo(
                    width: Int(dimensions.width),
                    height: Int(dimensions.height),
                    pixelFormat: fourCCString(subtype),
                    maxFPS: maxFPS
                )
            }
            .sorted { lhs, rhs in
                let lhsPixels = lhs.width * lhs.height
                let rhsPixels = rhs.width * rhs.height
                if lhsPixels != rhsPixels { return lhsPixels > rhsPixels }
                if lhs.isPanoramaCandidate != rhs.isPanoramaCandidate { return lhs.isPanoramaCandidate }
                return lhs.maxFPS > rhs.maxFPS
            }
    }

    func start(deviceID: String?, qualityMode: VideoQualityMode) async throws {
        guard let device = resolveDevice(deviceID: deviceID) else {
            throw NSError(domain: "tsjy.camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到可用摄像头"])
        }
        stop()
        configuredDeviceID = device.uniqueID
        selectedQualityMode = qualityMode
        savedDebugFrameCount = 0
        loggedFirstCaptureFrame = false
        prepareDebugFramesDirectory()
        encoder.setPreferredQualityMode(qualityMode)

        if device.localizedName.localizedCaseInsensitiveContains("insta360"),
           try startFFmpegCaptureIfPossible(deviceName: device.localizedName, qualityMode: qualityMode) {
            return
        }

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "tsjy.camera", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法添加摄像头输入"])
        }
        session.addInput(input)

        if session.canSetSessionPreset(inputPriorityPreset) {
            session.sessionPreset = inputPriorityPreset
            onStatus?("已启用输入优先采集模式")
        } else {
            onStatus?("当前系统不支持输入优先 preset，继续使用默认协商")
        }

        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "tsjy.camera", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法添加视频输出"])
        }
        session.addOutput(output)

        let selectedFormat = try selectPreferredFormat(for: device, targetMode: qualityMode)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: preferredOutputPixelFormat
        ]

        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        session.commitConfiguration()

        if !session.isRunning {
            session.startRunning()
        }

        let activeDimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let dimensions = CMVideoFormatDescriptionGetDimensions(selectedFormat.formatDescription)
        let selectedSubtype = fourCCString(CMFormatDescriptionGetMediaSubType(selectedFormat.formatDescription))
        let activeSubtype = fourCCString(CMFormatDescriptionGetMediaSubType(device.activeFormat.formatDescription))
        onStatus?("目标格式 \(dimensions.width)x\(dimensions.height) \(selectedSubtype)  档位 \(qualityMode.displayName)")
        onStatus?("实际 activeFormat \(activeDimensions.width)x\(activeDimensions.height) \(activeSubtype)")
        onStatus?("正在采集 \(device.localizedName)")
    }

    func stop(notify: Bool = true) {
        if recorder.isRecording {
            Task { [weak self] in
                _ = try? await self?.stopRecording()
            }
        }
        stopFFmpegCapture()
        if session.isRunning {
            session.stopRunning()
        }
        encoder.stop()
        output.setSampleBufferDelegate(nil, queue: nil)
        if notify {
            onStatus?("摄像头已停止")
        }
    }

    private func requestAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private func resolveDevice(deviceID: String?) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        let devices = discovery.devices
        if let deviceID, let match = devices.first(where: { $0.uniqueID == deviceID }) {
            return match
        }
        if let insta = devices.first(where: { $0.localizedName.localizedCaseInsensitiveContains("insta360") }) {
            return insta
        }
        return devices.first
    }

    private func startFFmpegCaptureIfPossible(deviceName: String, qualityMode: VideoQualityMode) throws -> Bool {
        guard let ffmpegPath = resolveFFmpegPath() else {
            onStatus?("未找到 ffmpeg，回退到 AVCapture")
            return false
        }

        let inputWidth = qualityMode.captureWidth
        let inputHeight = qualityMode.captureHeight
        let outputWidth = qualityMode.outputWidth
        let outputHeight = qualityMode.outputHeight
        let bytesPerRow = outputWidth * 2
        let frameByteCount = bytesPerRow * outputHeight
        ffmpegFrameIndex = 0
        currentCaptureMode = "FFmpeg"
        lastEmission = 0
        lastPreviewEmission = 0
        ffmpegPixelBufferPool = makePixelBufferPool(width: outputWidth, height: outputHeight)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-nostdin",
            "-loglevel", "warning",
            "-fflags", "nobuffer",
            "-flags", "low_delay",
            "-f", "avfoundation",
            "-framerate", "30",
            "-video_size", "\(inputWidth)x\(inputHeight)",
            "-pixel_format", "uyvy422",
            "-i", "\(deviceName):none",
            "-an",
            "-vf", "fps=30,scale=\(outputWidth):\(outputHeight):flags=fast_bilinear,format=uyvy422",
            "-fps_mode", "passthrough",
            "-f", "rawvideo",
            "-pix_fmt", "uyvy422",
            "pipe:1"
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        ffmpegOutputHandle = stdout.fileHandleForReading
        ffmpegErrorHandle = stderr.fileHandleForReading

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            DispatchQueue.main.async {
                self?.onStatus?("ffmpeg: \(trimmed)")
            }
        }

        try process.run()
        ffmpegProcess = process
        onStatus?("已切换为 ffmpeg 采集 \(inputWidth)x\(inputHeight) -> \(outputWidth)x\(outputHeight) uyvy422")

        ffmpegQueue.async { [weak self] in
            guard let self else { return }
            guard let handle = self.ffmpegOutputHandle else { return }
            var frameBuffer = Data(capacity: frameByteCount)
            var shouldStop = false

            while process.isRunning && !shouldStop {
                autoreleasepool {
                    let remaining = frameByteCount - frameBuffer.count
                    guard remaining > 0 else {
                        self.handleFFmpegFrame(
                            frameBuffer,
                            width: outputWidth,
                            height: outputHeight,
                            bytesPerRow: bytesPerRow
                        )
                        frameBuffer.removeAll(keepingCapacity: true)
                        return
                    }

                    let chunkSize = min(remaining, 1_048_576)
                    guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                        shouldStop = true
                        return
                    }
                    frameBuffer.append(chunk)

                    if frameBuffer.count == frameByteCount {
                        self.handleFFmpegFrame(
                            frameBuffer,
                            width: outputWidth,
                            height: outputHeight,
                            bytesPerRow: bytesPerRow
                        )
                        frameBuffer.removeAll(keepingCapacity: true)
                    } else if frameBuffer.count > frameByteCount {
                        frameBuffer.removeAll(keepingCapacity: true)
                        DispatchQueue.main.async {
                            self.onStatus?("ffmpeg 帧缓冲错位，已重置")
                        }
                    }
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.onStatus?("ffmpeg 采集结束 exit=\(proc.terminationStatus)")
            }
        }
        return true
    }

    private func stopFFmpegCapture() {
        ffmpegErrorHandle?.readabilityHandler = nil
        try? ffmpegOutputHandle?.close()
        try? ffmpegErrorHandle?.close()
        ffmpegOutputHandle = nil
        ffmpegErrorHandle = nil
        ffmpegProcess?.terminate()
        ffmpegProcess = nil
        ffmpegPixelBufferPool = nil
    }

    private func resolveFFmpegPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
            "/bin/ffmpeg"
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func handleFFmpegFrame(_ frameData: Data, width: Int, height: Int, bytesPerRow: Int) {
        let now = CACurrentMediaTime()
        guard now - lastEmission >= frameInterval else {
            return
        }
        lastEmission = now

        guard let pixelBuffer = makePixelBuffer(from: frameData, width: width, height: height, bytesPerRow: bytesPerRow) else {
            return
        }

        ffmpegFrameIndex += 1
        let pts = CMTime(value: ffmpegFrameIndex, timescale: CMTimeScale(preferredCaptureFPS))
        let duration = CMTime(value: 1, timescale: CMTimeScale(preferredCaptureFPS))

        if !loggedFirstCaptureFrame {
            loggedFirstCaptureFrame = true
            DispatchQueue.main.async {
                self.onStatus?("首帧捕获 \(width)x\(height) uyvy422 via ffmpeg")
            }
        }

        if now - lastPreviewEmission >= ffmpegPreviewInterval {
            lastPreviewEmission = now
            let rawCI = CIImage(cvPixelBuffer: pixelBuffer)
            let rawCG = context.createCGImage(rawCI, from: rawCI.extent)
            if let rawCG {
                saveDebugFrameIfNeeded(rawCG)
            }
            DispatchQueue.main.async {
                self.onPreviewFrames?(rawCG, rawCG)
            }
        }

        encoder.encode(
            pixelBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            wallClockTimestamp: Date().timeIntervalSince1970
        )
        try? recorder.append(pixelBuffer: pixelBuffer, at: pts)
    }

    private func makePixelBuffer(from frameData: Data, width: Int, height: Int, bytesPerRow: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        if let pool = ffmpegPixelBufferPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard status == kCVReturnSuccess else { return nil }
        } else {
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_422YpCbCr8,
                [
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ] as CFDictionary,
                &pixelBuffer
            )
            guard status == kCVReturnSuccess else { return nil }
        }
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        frameData.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress else { return }
            memcpy(baseAddress, source, min(frameData.count, bytesPerRow * height))
        }
        return pixelBuffer
    }

    private func makePixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        var pool: CVPixelBufferPool?
        let attributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 6
        ]
        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_422YpCbCr8,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            attributes as CFDictionary,
            pixelAttributes as CFDictionary,
            &pool
        )
        return status == kCVReturnSuccess ? pool : nil
    }

    private func selectPreferredFormat(for device: AVCaptureDevice, targetMode: VideoQualityMode) throws -> AVCaptureDevice.Format {
        let formats = device.formats
        guard let preferred = formats.max(by: { formatScore($0, targetMode: targetMode) < formatScore($1, targetMode: targetMode) }) else {
            throw NSError(domain: "tsjy.camera", code: 5, userInfo: [NSLocalizedDescriptionKey: "摄像头没有可用格式"])
        }

        try device.lockForConfiguration()
        device.activeFormat = preferred
        device.unlockForConfiguration()

        preferredOutputPixelFormat = CMFormatDescriptionGetMediaSubType(preferred.formatDescription)
        return preferred
    }

    private func formatScore(_ format: AVCaptureDevice.Format, targetMode: VideoQualityMode) -> Int {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        let fps = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        let pixels = width * height
        let aspectRatio = height > 0 ? Double(width) / Double(height) : 0
        let widthDelta = abs(width - targetMode.captureWidth)
        let heightDelta = abs(height - targetMode.captureHeight)
        let exactMatch = width == targetMode.captureWidth && height == targetMode.captureHeight

        var score = pixels
        if exactMatch {
            score += 2_000_000_000
        } else {
            score -= widthDelta * 200_000
            score -= heightDelta * 200_000
        }
        if abs(aspectRatio - 2.0) < 0.05 {
            score += 1_000_000_000
        }
        if subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            score += 100_000_000
        } else if subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            score += 80_000_000
        }
        if fps >= preferredCaptureFPS {
            score += 10_000_000
        } else {
            score += Int(fps * 100_000)
        }
        return score
    }

    private func prepareDebugFramesDirectory() {
        try? FileManager.default.createDirectory(at: debugFramesDirectory, withIntermediateDirectories: true)
        let existingFiles = (try? FileManager.default.contentsOfDirectory(at: debugFramesDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in existingFiles {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func saveDebugFrameIfNeeded(_ image: CGImage) {
        guard savedDebugFrameCount < 3 else { return }
        savedDebugFrameCount += 1
        let url = debugFramesDirectory.appendingPathComponent(String(format: "raw_frame_%03d.png", savedDebugFrameCount))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        if CGImageDestinationFinalize(destination) {
            onStatus?("已保存原始帧 \(url.lastPathComponent)")
        }
    }

    private func fourCCString(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        let string = String(bytes: bytes, encoding: .macOSRoman) ?? "\(value)"
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(value)" : trimmed
    }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastEmission >= frameInterval else { return }
        lastEmission = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if !loggedFirstCaptureFrame {
            loggedFirstCaptureFrame = true
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let pixelFormat = fourCCString(CVPixelBufferGetPixelFormatType(pixelBuffer))
            DispatchQueue.main.async {
                self.onStatus?("首帧捕获 \(width)x\(height) \(pixelFormat)")
            }
        }

        if now - lastPreviewEmission >= previewInterval {
            lastPreviewEmission = now
            let rawCI = CIImage(cvPixelBuffer: pixelBuffer)
            let rawCG = context.createCGImage(rawCI, from: rawCI.extent)
            if let rawCG {
                saveDebugFrameIfNeeded(rawCG)
            }
            
            DispatchQueue.main.async {
                self.onPreviewFrames?(rawCG, rawCG)
            }
        }

        encoder.encode(
            pixelBuffer: pixelBuffer,
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            duration: CMSampleBufferGetDuration(sampleBuffer),
            wallClockTimestamp: Date().timeIntervalSince1970
        )
        try? recorder.append(pixelBuffer: pixelBuffer, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
