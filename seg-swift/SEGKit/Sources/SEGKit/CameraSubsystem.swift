import Foundation

/// Camera API for extension apps.
public final class CameraSubsystem: @unchecked Sendable {
    internal let transport: TransportActor
    
    // Internal state
    internal var expectedBytes = 0
    internal var accumulator = Data()
    internal var capturing = false
    internal var nextExpectedSeq = 0
    internal var onCapture: ((Data) -> Void)?
    internal var onError: ((Int) -> Void)?
    private var currentMode: CameraMode = .still
    internal private(set) var streamFrameCount = 0
    internal var lastError: Int? = nil

    public var isStreaming: Bool { currentMode.isStreamMode && capturing }
    internal var isStreamMode: Bool { currentMode.isStreamMode }
    
    internal init(transport: TransportActor) {
        self.transport = transport
    }
    
    /// Set camera mode before capturing.
    public func setMode(
        _ mode: CameraMode,
        resolution: CameraResolution = .qvga,
        quality: CameraQuality = .standard
    ) async {
        currentMode = mode
        // Stream modes support ONLY QVGA (Java: CAMERA_JPEG_STREAM_SUPPORT_RESOLUTION)
        let effectiveResolution: CameraResolution = mode.isStreamMode ? .qvga : resolution
        // Wire: 0xce [len=4] [quality] [resolution] [mode] [fps]
        await transport.send([
            0xce, 0x00, 0x04,
            quality.rawValue, effectiveResolution.rawValue, mode.rawValue, mode.fpsByte
        ], label: "CameraSetMode(\(mode),res=\(effectiveResolution.rawValue),q=\(quality.rawValue),fps=\(mode.fpsByte))")
    }
    
    /// Capture a single still photo. Result delivered via GlassesDelegate.
    public func captureStill(
        resolution: CameraResolution = .qvga,
        quality: CameraQuality = .fine
    ) async {
        guard !capturing else { return }
        await setMode(.still, resolution: resolution, quality: quality)
        try? await Task.sleep(for: .milliseconds(300))
        // Start camera sensor
        await transport.send([0x38, 0x00, 0x04, 0x13, 0x06, 0x00, 0x00],
                             label: "SensorStart(camera)")
        try? await Task.sleep(for: .milliseconds(500))
        await transport.send([0xb4, 0x00, 0x00], label: "CaptureRequest")
    }
    
    /// Start continuous JPEG stream.
    /// - Parameter mode: `.streamLow` (7.5fps) or `.streamHigh` (15fps). Defaults to `.streamLow`.
    /// - Note: Stream modes are always QVGA (320×240) regardless of resolution parameter.
    public func startStream(
        mode: CameraMode = .streamLow,
        quality: CameraQuality = .standard
    ) async {
        let effectiveMode = mode.isStreamMode ? mode : .streamLow
        await setMode(effectiveMode, resolution: .qvga, quality: quality)
        try? await Task.sleep(for: .milliseconds(300))
        await transport.send([0x38, 0x00, 0x04, 0x13, 0x06, 0x00, 0x00],
                             label: "SensorStart(camera)")
        await transport.send([0xb4, 0x00, 0x00], label: "CaptureRequest")
    }
    
    /// Stop camera.
    public func stop() async {
        await transport.send([0xb8, 0x00, 0x01, 0x00], label: "CameraCancel")
        capturing = false
        accumulator = Data()
    }
    
    // MARK: - Internal handlers (called by ProtocolActor)
    
    internal func handleCaptureResponse(_ payload: Data) {
        guard payload.count >= 6 else { return }
        let status = payload[0]
        if status == 0 {
            // jpeg_size is big-endian (Java ByteBuffer default)
            expectedBytes = (Int(payload[2]) << 24) | (Int(payload[3]) << 16) |
                           (Int(payload[4]) << 8) | Int(payload[5])
            accumulator = Data()
            nextExpectedSeq = 0
            capturing = true
        } else {
            lastError = Int(status)
            onError?(Int(status))
        }
    }
    
    internal func handleChunk(_ payload: Data) -> [UInt8]? {
        guard payload.count > 3 else { return nil }
        let seq = Int(payload[0])
        let ack: [UInt8] = [0xf1, 0x00, 0x01, payload[0]]
        guard capturing else {
            print("  [cam] chunk seq=\(seq) but NOT capturing! payload[0..3]=\(payload.prefix(4).map{String(format:"%02x",$0)}.joined(separator:" "))")
            return ack
        }
        // Accept all chunks (don't dedup — BT delivers in order)
        accumulator.append(payload[3...])
        nextExpectedSeq = seq + 1
        if seq % 20 == 0 {
            print("  [cam] chunk #\(seq) +\(payload.count-3)B acc=\(accumulator.count)/\(expectedBytes)B")
        }
        return ack
    }
    
    internal func handleDone(_ payload: Data) -> Data? {
        capturing = false
        let jpeg = accumulator
        accumulator = Data()
        if currentMode.isStreamMode {
            streamFrameCount += 1
        }
        return jpeg.isEmpty ? nil : jpeg
    }
}
