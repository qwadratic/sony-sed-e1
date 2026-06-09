import Foundation

/// Wire protocol command IDs. Internal to SDK — extension apps never see these.
internal enum Cmd {
    // Handshake
    static let protocolVersion: UInt8 = 0x0a
    static let settingsStatusReq: UInt8 = 0x71
    static let settingsStatusRes: UInt8 = 0x72
    static let versionReq: UInt8 = 0x07
    static let versionRes: UInt8 = 0x08
    static let newHostApp: UInt8 = 0x85
    static let fotaStatus: UInt8 = 0x81
    static let syncResponse: UInt8 = 0xff
    static let openAppStartReq: UInt8 = 0x30
    static let openAppStartRes: UInt8 = 0x31
    
    // Display
    static let layoutInit: UInt8 = 0xe0
    static let layoutPlaceRemove: UInt8 = 0xe7
    static let imageAck: UInt8 = 0xe8
    static let layoutEventNotify: UInt8 = 0xe5
    
    // Camera
    static let cameraSetMode: UInt8 = 0xce
    static let captureRequest: UInt8 = 0xb4
    static let captureResponse: UInt8 = 0xb5
    static let captureData: UInt8 = 0xb6
    static let captureDone: UInt8 = 0xb7
    static let captureCancel: UInt8 = 0xb8
    static let captureDataAck: UInt8 = 0xf1
    
    // Sensors
    static let sensorStart: UInt8 = 0x38
    static let sensorStop: UInt8 = 0x39
    static let accelData: UInt8 = 0x3a
    static let batterySensor: UInt8 = 0x3e
    static let gyroData: UInt8 = 0xbc
    static let magData: UInt8 = 0xbd
    static let lightData: UInt8 = 0x3b
    static let rotationData: UInt8 = 0xbb
    
    // Input
    static let levelNotification: UInt8 = 0x06
    static let ping: UInt8 = 0x05
    
    // WiFi
    static let wifiStatusReq: UInt8 = 0x90
    static let wifiStatusRes: UInt8 = 0x91
    static let wifiTurnOn: UInt8 = 0x92
    static let wifiTurnOff: UInt8 = 0x93
    static let wifiConnectReq: UInt8 = 0x94
    static let wifiConnectStatus: UInt8 = 0x95
    static let wifiSwitchPathReq: UInt8 = 0x96
    static let wifiSwitchPathRes: UInt8 = 0x97
}
