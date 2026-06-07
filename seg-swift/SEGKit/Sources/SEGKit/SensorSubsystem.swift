import Foundation

/// Sensor API for extension apps.
public final class SensorSubsystem: @unchecked Sendable {
    /// Current sensor reading (updated on each sensor event).
    public private(set) var current = SensorReading()
    
    internal init() {}
    
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
