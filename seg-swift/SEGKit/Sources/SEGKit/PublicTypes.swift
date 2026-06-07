import Foundation

// MARK: - Display

public enum DisplayConstants {
    public static let width = 419
    public static let height = 138
    public static let pixelCount = width * height  // 57822
}

// MARK: - Camera

public enum CameraMode: UInt8, Sendable {
    case still = 0
    case stillToFile = 1
    case streamLowRate = 2   // ~7.5 fps
    case streamHighRate = 3  // ~15 fps
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

public struct SensorReading: Sendable {
    public var accelerometer: SIMD3<Float>
    public var gyroscope: SIMD3<Float>
    public var magnetometer: SIMD3<Float>
    public var timestamp: UInt64
    
    public init(accelerometer: SIMD3<Float> = .zero,
                gyroscope: SIMD3<Float> = .zero,
                magnetometer: SIMD3<Float> = .zero,
                timestamp: UInt64 = 0) {
        self.accelerometer = accelerometer
        self.gyroscope = gyroscope
        self.magnetometer = magnetometer
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
