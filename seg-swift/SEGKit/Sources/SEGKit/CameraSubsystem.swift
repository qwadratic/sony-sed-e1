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

    public var isStreaming: Bool { currentMode == .movie && capturing }
    internal var isMovieMode: Bool { currentMode == .movie }
    
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
        await transport.send([
            0xce, 0x00, 0x04,
            mode.rawValue, resolution.rawValue, quality.rawValue, 0x00
        ], label: "CameraSetMode")
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
    public func startStream(
        resolution: CameraResolution = .qvga,
        quality: CameraQuality = .standard
    ) async {
        await setMode(.movie, resolution: resolution, quality: quality)
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
            expectedBytes = Int(payload[2]) | (Int(payload[3]) << 8) |
                           (Int(payload[4]) << 16) | (Int(payload[5]) << 24)
            accumulator = Data()
            nextExpectedSeq = 0
            capturing = true
        } else {
            lastError = Int(status)
            onError?(Int(status))
        }
    }
    
    internal func handleChunk(_ payload: Data) -> [UInt8]? {
        guard capturing, payload.count > 3 else { return nil }
        let seq = Int(payload[0])
        let ack: [UInt8] = [0xf1, 0x00, 0x01, payload[0]]
        guard seq == nextExpectedSeq else { return ack }
        accumulator.append(payload[3...])
        nextExpectedSeq += 1
        return ack
    }
    
    internal func handleDone(_ payload: Data) -> Data? {
        capturing = false
        let jpeg = accumulator
        accumulator = Data()
        if currentMode == .movie {
            streamFrameCount += 1
        }
        return jpeg.isEmpty ? nil : jpeg
    }
}
