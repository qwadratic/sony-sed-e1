import Foundation

/// Debug log level — controls what gets printed to stdout.
public enum LogLevel: Int, Comparable, Sendable {
    case silent = 0
    case normal = 1    // phase changes, errors
    case verbose = 2   // + sensor/camera/input events
    case debug = 3     // + every wire frame TX/RX with hex bytes
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Structured event logger. Writes JSONL to /tmp/seg-events.jsonl AND prints to stdout.
public final class EventLogger: @unchecked Sendable {
    private let fileHandle: FileHandle?
    private let path: String
    public var level: LogLevel = .normal
    
    /// Command name lookup for hex display
    private static let cmdNames: [UInt8: String] = [
        0x0a: "ProtocolVersion", 0x71: "SettingsStatusReq", 0x72: "SettingsStatusRes",
        0x07: "VersionReq", 0x08: "VersionRes", 0x85: "NewHostApp", 0x81: "FotaStatus",
        0xff: "SyncResponse", 0x30: "OpenAppStartReq", 0x31: "OpenAppStartRes",
        0x06: "LevelNotification", 0x05: "Ping",
        0xe0: "LayoutInit", 0xe7: "LayoutPlaceRemove", 0xe8: "ImageAck",
        0xe5: "LayoutEventNotify", 0xe9: "DisplayOnOff",
        0xce: "CameraSetMode", 0xb4: "CaptureReq", 0xb5: "CaptureResp",
        0xb6: "CaptureData", 0xb7: "CaptureDone", 0xb8: "CaptureCancel",
        0xf1: "CaptureDataAck",
        0x38: "SensorStart", 0x39: "SensorStop",
        0x3a: "Accelerometer", 0xbc: "Gyroscope", 0xbd: "Magnetometer",
        0x3b: "Light", 0xbb: "RotationVector",
        0x90: "WifiStatusReq", 0x91: "WifiStatusRes",
        0x92: "WifiTurnOn", 0x93: "WifiTurnOff",
        0x94: "WifiConnectReq", 0x95: "WifiConnectStatus",
        0x96: "WifiSwitchPathReq", 0x97: "WifiSwitchPathRes",
    ]
    
    public init(path: String = "/tmp/seg-events.jsonl") {
        self.path = path
        FileManager.default.createFile(atPath: path, contents: nil)
        self.fileHandle = FileHandle(forWritingAtPath: path)
    }
    
    public func log(_ type: String, _ fields: [String: Any]) {
        var dict = fields
        dict["type"] = type
        dict["ts"] = Date().timeIntervalSince1970 * 1000
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           var line = String(data: data, encoding: .utf8) {
            line += "\n"
            fileHandle?.write(line.data(using: .utf8)!)
        }
    }
    
    /// Log a transmitted wire frame.
    public func logTX(_ bytes: [UInt8], label: String) {
        guard level >= .debug else { return }
        let cmd = bytes.first ?? 0
        let name = Self.cmdNames[cmd] ?? label
        let hex = bytes.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
        let suffix = bytes.count > 20 ? "... (\(bytes.count)B)" : ""
        print("  → TX \(name) [\(bytes.count)B] \(hex)\(suffix)")
        fflush(stdout)
    }
    
    /// Log a received wire frame.
    public func logRX(cmdId: UInt8, payload: Data) {
        guard level >= .debug else { return }
        let name = Self.cmdNames[cmdId] ?? String(format: "0x%02x", cmdId)
        let hex = ([cmdId] + Array(payload.prefix(19))).map { String(format: "%02x", $0) }.joined(separator: " ")
        let suffix = payload.count > 19 ? "... (\(payload.count + 1)B)" : ""
        print("  ← RX \(name) [\(payload.count + 3)B] \(hex)\(suffix)")
        fflush(stdout)
    }
    
    /// Log a debug message at a given level.
    public func debug(_ msg: String, minLevel: LogLevel = .debug) {
        guard level >= minLevel else { return }
        print("  [dbg] \(msg)")
        fflush(stdout)
    }
    
    deinit { fileHandle?.closeFile() }
}
