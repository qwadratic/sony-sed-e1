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
    public func start(_ type: SensorType, rate: UInt8 = 0x06) async {
        await transport.send(
            [0x38, 0x00, 0x04, type.rawValue, rate, 0x00, 0x00],
            label: "SensorStart(\(type))"
        )
    }
    
    /// Stop receiving sensor data.
    public func stop(_ type: SensorType) async {
        await transport.send(
            [0x39, 0x00, 0x04, type.rawValue, 0x00, 0x00, 0x00],
            label: "SensorStop(\(type))"
        )
    }
    
    // MARK: - Internal handlers
    
    internal func handleAccelerometer(_ payload: Data) -> SensorReading {
        guard payload.count >= 12 else { return current }
        current.accelerometer = extractSIMD3(payload)
        return current
    }
    
    internal func handleGyroscope(_ payload: Data) -> SensorReading {
        guard payload.count >= 12 else { return current }
        current.gyroscope = extractSIMD3(payload)
        return current
    }
    
    internal func handleMagnetometer(_ payload: Data) -> SensorReading {
        guard payload.count >= 12 else { return current }
        current.magnetometer = extractSIMD3(payload)
        return current
    }
    
    internal func handleLight(_ payload: Data) -> SensorReading {
        guard payload.count >= 4 else { return current }
        let value = payload.withUnsafeBytes { buf in
            buf.load(fromByteOffset: 0, as: Float.self)
        }
        current.light = value
        return current
    }
    
    private func extractSIMD3(_ data: Data) -> SIMD3<Float> {
        data.withUnsafeBytes { buf in
            SIMD3(
                buf.load(fromByteOffset: 0, as: Float.self),
                buf.load(fromByteOffset: 4, as: Float.self),
                buf.load(fromByteOffset: 8, as: Float.self)
            )
        }
    }
}
