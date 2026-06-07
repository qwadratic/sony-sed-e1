import Foundation

/// Sensor API for extension apps.
public final class SensorSubsystem: @unchecked Sendable {
    internal let transport: TransportActor
    /// Current sensor reading (updated on each sensor event).
    public private(set) var current = SensorReading()
    
    internal init(transport: TransportActor) {
        self.transport = transport
    }
    
    // MARK: - Public API
    
    /// Start receiving sensor data of given type.
    /// Rate: 1=FASTEST, 2=GAME, 3=NORMAL, 4=UI, 6=custom interval (not yet supported).
    public func start(_ type: SensorType, rate: UInt8 = 0x03) async {
        if rate == 6 {
            // Custom interval mode — not supported yet, fall back to NORMAL
            await transport.send(
                [0x38, 0x00, 0x02, type.rawValue, 0x03],
                label: "SensorStart(\(type))"
            )
        } else {
            await transport.send(
                [0x38, 0x00, 0x02, type.rawValue, rate],
                label: "SensorStart(\(type))"
            )
        }
    }
    
    /// Stop receiving sensor data.
    public func stop(_ type: SensorType) async {
        await transport.send(
            [0x39, 0x00, 0x01, type.rawValue],
            label: "SensorStop(\(type))"
        )
    }
    
    // MARK: - Internal handlers
    
    // All sensor payloads have 8-byte header: [accuracy:4B BE int][timestamp:4B BE int][values...]

    internal func handleAccelerometer(_ payload: Data) -> SensorReading {
        // payload: [accuracy:4B][timestamp:4B][x:4B float][y:4B float][z:4B float]
        guard payload.count >= 20 else { return current }
        current.accelerometer = extractSIMD3(payload, offset: 8)
        current.timestamp = extractTimestamp(payload)
        return current
    }
    
    internal func handleGyroscope(_ payload: Data) -> SensorReading {
        guard payload.count >= 20 else { return current }
        current.gyroscope = extractSIMD3(payload, offset: 8)
        current.timestamp = extractTimestamp(payload)
        return current
    }
    
    internal func handleMagnetometer(_ payload: Data) -> SensorReading {
        guard payload.count >= 20 else { return current }
        current.magnetometer = extractSIMD3(payload, offset: 8)
        current.timestamp = extractTimestamp(payload)
        return current
    }
    
    internal func handleLight(_ payload: Data) -> SensorReading {
        // payload: [accuracy:4B][timestamp:4B][lightValue:4B int]
        guard payload.count >= 12 else { return current }
        current.light = Float(extractInt32BE(payload, offset: 8))
        current.timestamp = extractTimestamp(payload)
        return current
    }
    
    /// Handle 0x3e BatterySensor — [accuracy:4B][timestamp:4B][batteryPct:4B int][charging:4B int]
    internal func handleBattery(_ payload: Data) -> SensorReading {
        guard payload.count >= 16 else { return current }
        current.battery = Int(extractInt32BE(payload, offset: 8))
        current.batteryRaw = Array(payload)
        current.timestamp = extractTimestamp(payload)
        return current
    }
    
    private func extractSIMD3(_ data: Data, offset: Int) -> SIMD3<Float> {
        guard data.count >= offset + 12 else { return .zero }
        return data.withUnsafeBytes { buf in
            SIMD3(
                buf.load(fromByteOffset: offset, as: Float.self),
                buf.load(fromByteOffset: offset + 4, as: Float.self),
                buf.load(fromByteOffset: offset + 8, as: Float.self)
            )
        }
    }
    
    private func extractTimestamp(_ data: Data) -> UInt64 {
        guard data.count >= 8 else { return 0 }
        return UInt64(data[4]) << 24 | UInt64(data[5]) << 16 |
               UInt64(data[6]) << 8  | UInt64(data[7])
    }
    
    private func extractInt32BE(_ data: Data, offset: Int) -> Int32 {
        guard data.count >= offset + 4 else { return 0 }
        return Int32(data[offset]) << 24 | Int32(data[offset+1]) << 16 |
               Int32(data[offset+2]) << 8 | Int32(data[offset+3])
    }
}
