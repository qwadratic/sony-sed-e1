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
    case battery = 0x03
    case rotationVector = 0x0c
    case gyroscope = 0x0d
    case magnetometer = 0x0e
    case light = 0x10
    case camera = 0x13
}

public struct SensorReading: Sendable {
    public var accelerometer: SIMD3<Float>
    public var gyroscope: SIMD3<Float>
    public var magnetometer: SIMD3<Float>
    public var light: Float
    public var battery: Int            // 0-100 percentage from 0x3e payload
    public var batteryRaw: [UInt8]     // full 16-byte 0x3e payload for debug
    public var timestamp: UInt64
    
    public init(accelerometer: SIMD3<Float> = .zero,
                gyroscope: SIMD3<Float> = .zero,
                magnetometer: SIMD3<Float> = .zero,
                light: Float = 0,
                battery: Int = 0,
                batteryRaw: [UInt8] = [],
                timestamp: UInt64 = 0) {
        self.accelerometer = accelerometer
        self.gyroscope = gyroscope
        self.magnetometer = magnetometer
        self.light = light
        self.battery = battery
        self.batteryRaw = batteryRaw
        self.timestamp = timestamp
    }
}

// MARK: - Input

public enum InputEvent: Sendable, Equatable, CustomStringConvertible {
    // Touchpad
    case tap                    // 0x12
    case longPress              // 0x13
    case swipeLeft              // 0x14
    case swipeRight             // 0x15
    case fingerOn               // 0x11
    case fingerOff              // 0x10
    
    // Jog dial
    case jogPress               // 0x01
    case jogLongPress           // 0x02
    case jogLongRelease         // 0x03
    case jogRotateCW            // 0x04
    case jogRotateCCW           // 0x05
    
    // Hardware buttons
    case backButton             // 0x08
    case backLongPress          // 0x0a
    case cameraButton           // 0x09
    case cameraLongPress        // 0x0f
    case pttPress               // 0x0b
    case pttRelease             // 0x0c
    
    // Display
    case displayOff             // 0x0d
    case displayOn              // 0x0e
    
    case unknown(code: UInt8)
    
    public var description: String {
        switch self {
        case .tap: return "tap"
        case .longPress: return "longPress"
        case .swipeLeft: return "swipeLeft"
        case .swipeRight: return "swipeRight"
        case .fingerOn: return "fingerOn"
        case .fingerOff: return "fingerOff"
        case .jogPress: return "jogPress"
        case .jogLongPress: return "jogLongPress"
        case .jogLongRelease: return "jogLongRelease"
        case .jogRotateCW: return "jogCW"
        case .jogRotateCCW: return "jogCCW"
        case .backButton: return "back"
        case .backLongPress: return "backLong"
        case .cameraButton: return "camera"
        case .cameraLongPress: return "cameraLong"
        case .pttPress: return "pttPress"
        case .pttRelease: return "pttRelease"
        case .displayOff: return "displayOff"
        case .displayOn: return "displayOn"
        case .unknown(let c): return "unknown(0x\(String(format: "%02x", c)))"
        }
    }
}

// MARK: - Power Mode

public enum PowerMode: UInt8, Sendable {
    case normal = 1   // Bluetooth
    case high = 0     // WiFi
}
