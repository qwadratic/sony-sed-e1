import Foundation

// MARK: - Display

public enum DisplayConstants {
    public static let width = 419
    public static let height = 138
    public static let pixelCount = width * height  // 57822
}

// MARK: - Camera

public enum CameraMode: UInt8, Sendable {
    case still = 0    // single frame capture
    case movie = 1    // continuous JPEG stream
}

public enum CameraResolution: UInt8, Sendable {
    case threeMP = 0
    case sxga = 1     // 1280×1024
    case xga = 2      // 1024×768
    case svga = 3     // 800×600
    case vga = 4      // 640×480
    case hvga = 5     // 480×320
    case qvga = 6     // 320×240
    case qqvga = 7    // 160×120
}

public enum CameraQuality: UInt8, Sendable {
    case standard = 1
    case fine = 2
    case superFine = 3
}

// MARK: - Sensors

public enum SensorType: UInt8, Sendable {
    case accelerometer = 0x01
    case magnetometer = 0x02
    case gyroscope = 0x04
    case light = 0x05
    case camera = 0x13
}

public struct SensorReading: Sendable {
    public var accelerometer: SIMD3<Float>
    public var gyroscope: SIMD3<Float>
    public var magnetometer: SIMD3<Float>
    public var light: Float
    public var timestamp: UInt64
    
    public init(accelerometer: SIMD3<Float> = .zero,
                gyroscope: SIMD3<Float> = .zero,
                magnetometer: SIMD3<Float> = .zero,
                light: Float = 0,
                timestamp: UInt64 = 0) {
        self.accelerometer = accelerometer
        self.gyroscope = gyroscope
        self.magnetometer = magnetometer
        self.light = light
        self.timestamp = timestamp
    }
}

// MARK: - Input

public enum InputEvent: Sendable, Equatable {
    case tap
    case longPress
    case swipeLeft
    case swipeRight
    case swipeUp
    case swipeDown
    case touchPress(x: Int, y: Int)
    case touchRelease(x: Int, y: Int)
}

// MARK: - Power Mode

public enum PowerMode: UInt8, Sendable {
    case normal = 1   // Bluetooth
    case high = 0     // WiFi
}
