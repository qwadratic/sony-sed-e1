// STALE: This file contains placeholder protocol guesses from before the RE was completed.
// See glasses-tool.swift for the working implementation.

/**
 GlassesMiddleware.swift
 Sony SED-E1 macOS middleware
 
 Two connection modes:
   1. BT SPP (IOBluetooth.framework) — direct to glasses
   2. ADB bridge — forward local socket from Android phone via adb forward
 
 Both expose the same GlassesDelegate protocol.
 
 Build: macOS 12+, no additional dependencies.
*/

import Foundation
import IOBluetooth
import Network

// MARK: - Protocol

protocol GlassesDelegate: AnyObject {
    func glassesDidConnect()
    func glassesDidDisconnect()
    func glassesDidReceive(data: Data)
}

// MARK: - Display command builder

struct GlassesCommands {
    
    /// Width × height of the glasses display
    static let displayWidth  = 419
    static let displayHeight = 138
    
    /**
     Build a "show bitmap" command from raw 419×138 pixel data.
     
     Pixel format: 1 bit per pixel, row-major, MSB first.
     White (0xFF) → green LED on. Black (0x00) → LED off.
     
     NOTE: Exact framing bytes still need to be captured from BT HCI snoop.
           This builds the PAYLOAD — wrap it in the protocol frame.
     */
    static func showBitmapPayload(pixels: [[Bool]]) -> Data {
        var bits = Data()
        for row in pixels {
            var byte: UInt8 = 0
            for (i, px) in row.enumerated() {
                if px { byte |= (0x80 >> (i % 8)) }
                if i % 8 == 7 { bits.append(byte); byte = 0 }
            }
            if row.count % 8 != 0 { bits.append(byte) }
        }
        return bits
    }
    
    /**
     Build display command from CGImage.
     Converts to 1-bit monochrome (threshold at 50% luminance).
     */
    static func showBitmapPayload(cgImage: CGImage) -> Data {
        guard let ctx = CGContext(
            data: nil,
            width: displayWidth, height: displayHeight,
            bitsPerComponent: 8, bytesPerRow: displayWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return Data() }
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0,
                                      width: displayWidth, height: displayHeight))
        guard let pixelData = ctx.data else { return Data() }
        let ptr = pixelData.bindMemory(to: UInt8.self, capacity: displayWidth * displayHeight)
        
        var bits = Data(capacity: (displayWidth * displayHeight) / 8 + 1)
        var byte: UInt8 = 0
        for i in 0 ..< displayWidth * displayHeight {
            let luma = ptr[i]
            if luma > 127 { byte |= (0x80 >> (i % 8)) }
            if i % 8 == 7 { bits.append(byte); byte = 0 }
        }
        if (displayWidth * displayHeight) % 8 != 0 { bits.append(byte) }
        return bits
    }
}

// MARK: - Protocol framing (PLACEHOLDER — needs HCI snoop to fill in)

struct ProtocolFrame {
    /**
     Frame a payload for sending over RFCOMM / TCP.
     
     *** THESE VALUES ARE PLACEHOLDERS ***
     Real values come from HCI snoop capture.
     
     Hypothesis based on similar Sony protocols:
       [SOF 1B] [CMD 1B] [LEN 2B LE] [PAYLOAD] [CRC 1B]
     
     See PROTOCOL_MAP.md for RE steps.
    */
    
    static let SOF: UInt8 = 0x02          // Start of frame (guess)
    static let CMD_DISPLAY: UInt8 = 0x10  // Display command (guess)
    static let CMD_TOUCH_ACK: UInt8 = 0x20
    
    static func frame(command: UInt8, payload: Data) -> Data {
        var frame = Data()
        frame.append(SOF)
        frame.append(command)
        let len = UInt16(payload.count)
        frame.append(UInt8(len & 0xFF))
        frame.append(UInt8(len >> 8))
        frame.append(contentsOf: payload)
        // CRC: XOR of all bytes (placeholder)
        let crc = frame.reduce(UInt8(0)) { $0 ^ $1 }
        frame.append(crc)
        return frame
    }
}

// MARK: - Mode 1: BT SPP via IOBluetooth

class BluetoothGlassesConnection: NSObject {
    
    weak var delegate: GlassesDelegate?
    
    private var device: IOBluetoothDevice?
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    
    /// SPP channel ID (1 is typical; may need to query SDP record)
    private var channelID: BluetoothRFCOMMChannelID = 1
    
    // MARK: - Connection
    
    /**
     Connect to glasses by BT MAC address.
     
     How to get the MAC:
       - Read NFC tag on controller (contains BT MAC in NDEF record)
       - Or: pair in system BT settings first, then use device.addressString
     
     - parameter address: "XX:XX:XX:XX:XX:XX" format
    */
    func connect(to address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            print("[BT] Could not create device for address \(address)")
            return
        }
        self.device = device
        
        // Query SDP to find the correct SPP channel
        // The glasses advertise SPP — channel ID might be 1, 3, or 5
        querySPP(device: device) { [weak self] channelID in
            guard let self = self else { return }
            self.channelID = channelID ?? 1
            self.openRFCOMM()
        }
    }
    
    private func querySPP(device: IOBluetoothDevice, completion: @escaping (BluetoothRFCOMMChannelID?) -> Void) {
        // Perform SDP query for Serial Port Profile
        device.performSDPQuery(nil)
        
        // Find SPP service record
        let sppUUID = IOBluetoothSDPUUID.uuid16(0x1101) // SPP UUID
        if let services = device.services as? [IOBluetoothSDPServiceRecord] {
            for service in services {
                if service.hasServiceFromArray([sppUUID]) {
                    var channelID: BluetoothRFCOMMChannelID = 0
                    if service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                        print("[BT] Found SPP on channel \(channelID)")
                        completion(channelID)
                        return
                    }
                }
            }
        }
        
        print("[BT] SDP query found no SPP — defaulting to channel 1")
        completion(1)
    }
    
    private func openRFCOMM() {
        guard let device = device else { return }
        
        let result = device.openRFCOMMChannelAsync(
            &rfcommChannel,
            withChannelID: channelID,
            delegate: self
        )
        
        if result == kIOReturnSuccess {
            print("[BT] RFCOMM channel opening to channel \(channelID)...")
        } else {
            print("[BT] Failed to open RFCOMM: \(result)")
        }
    }
    
    func disconnect() {
        rfcommChannel?.close()
        device?.closeConnection()
        rfcommChannel = nil
        device = nil
    }
    
    // MARK: - Send
    
    func send(_ data: Data) {
        guard let channel = rfcommChannel else {
            print("[BT] Not connected — cannot send")
            return
        }
        
        var mutableData = data
        mutableData.withUnsafeMutableBytes { ptr in
            guard let baseAddr = ptr.baseAddress else { return }
            channel.writeAsync(baseAddr, length: UInt16(data.count), refcon: nil)
        }
    }
    
    func showBitmap(_ cgImage: CGImage) {
        let payload = GlassesCommands.showBitmapPayload(cgImage: cgImage)
        let frame = ProtocolFrame.frame(command: ProtocolFrame.CMD_DISPLAY, payload: payload)
        send(frame)
    }
}

// MARK: - IOBluetoothRFCOMMChannelDelegate

extension BluetoothGlassesConnection: IOBluetoothRFCOMMChannelDelegate {
    
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            print("[BT] RFCOMM connected!")
            delegate?.glassesDidConnect()
        } else {
            print("[BT] RFCOMM open failed: \(error)")
        }
    }
    
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        print("[BT] RFCOMM closed")
        delegate?.glassesDidDisconnect()
        self.rfcommChannel = nil
    }
    
    func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        let data = Data(bytes: dataPointer, count: dataLength)
        print("[BT] Received \(dataLength) bytes: \(data.hexDescription)")
        delegate?.glassesDidReceive(data: data)
    }
    
    func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        refcon: UnsafeMutableRawPointer!,
        status error: IOReturn
    ) {
        if error != kIOReturnSuccess {
            print("[BT] Write failed: \(error)")
        }
    }
}

// MARK: - Mode 2: ADB Socket Bridge

/**
 Bridges the local UNIX socket that the SmartEyeglassEmulator uses to macOS TCP.
 
 Setup:
   1. Connect Android phone with glasses paired via USB
   2. Run: adb forward tcp:7001 localabstract:com.sony.smarteyeglass.MONITOR_SOCKET
   3. GlassesADBBridge.connect(host: "127.0.0.1", port: 7001)
 
 This bypasses Bluetooth entirely — the phone handles BT/WiFi to glasses,
 and we talk the local socket protocol that the SmartEyeglassEmulator uses.
 
 Advantage: works TODAY with the tools we have.
 No protocol RE needed for the BT layer.
*/
class GlassesADBBridge: NSObject {
    
    weak var delegate: GlassesDelegate?
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "dev.glasses.adb")
    
    func connect(host: String = "127.0.0.1", port: UInt16 = 7001) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        connection = NWConnection(to: endpoint, using: .tcp)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[ADB] Connected to bridge port \(port)")
                self?.delegate?.glassesDidConnect()
                self?.receiveLoop()
            case .failed(let error):
                print("[ADB] Connection failed: \(error)")
                self?.delegate?.glassesDidDisconnect()
            case .cancelled:
                self?.delegate?.glassesDidDisconnect()
            default:
                break
            }
        }
        connection?.start(queue: queue)
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
    }
    
    func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[ADB] Send error: \(error)")
            }
        })
    }
    
    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                print("[ADB] Received \(data.count) bytes")
                self?.delegate?.glassesDidReceive(data: data)
            }
            if isComplete || error != nil {
                self?.delegate?.glassesDidDisconnect()
            } else {
                self?.receiveLoop()
            }
        }
    }
}

// MARK: - Shell helper: set up ADB forward

extension GlassesADBBridge {
    
    /**
     Automatically run `adb forward` for all known glasses sockets.
     Call this before connect().
    */
    static func setupADBForward() {
        let sockets: [(localPort: Int, socket: String)] = [
            (7001, "com.sony.smarteyeglass.MONITOR_SOCKET"),  // main control
            // Add more as discovered from RE:
            // (7002, "com.sony.smarteyeglass.SENSOR_SOCKET"),
            // (7003, "com.sony.smarteyeglass.CAMERA_SOCKET"),
        ]
        
        for (port, socket) in sockets {
            let task = Process()
            task.launchPath = "/opt/homebrew/bin/adb"
            task.arguments = ["forward", "tcp:\(port)", "localabstract:\(socket)"]
            task.launch()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                print("[ADB] Forwarded tcp:\(port) → \(socket)")
            } else {
                print("[ADB] Forward failed for \(socket) — is adb running?")
            }
        }
    }
}

// MARK: - HCI Snoop capture helper

/**
 Helper to capture the BT HCI log from a connected Android device.
 Run this while operating the glasses to capture the raw BT protocol.
*/
struct HCISnoop {
    
    static func enable() {
        shell("adb", "shell", "setprop", "bluetooth.btsnoopenable", "true")
        shell("adb", "shell", "setprop", "persist.bluetooth.btsnoopenable", "true")
        print("[Snoop] HCI snoop enabled. Restart Bluetooth on phone to activate.")
    }
    
    static func pull(to path: String = "/tmp/btsnoop_hci.log") {
        // Try both common paths
        let paths = [
            "/sdcard/btsnoop_hci.log",
            "/data/misc/bluetooth/logs/btsnoop_hci.log",
            "/data/log/bt/btsnoop_hci.log",
        ]
        
        for btPath in paths {
            let result = shell("adb", "pull", btPath, path)
            if result == 0 {
                print("[Snoop] Pulled HCI log to \(path)")
                print("[Snoop] Open in Wireshark: File → Import from HCI dump")
                print("[Snoop] Filter: rfcomm || btl2cap")
                return
            }
        }
        
        print("[Snoop] Could not find HCI log. Try: adb shell find /data -name 'btsnoop*' 2>/dev/null")
    }
    
    @discardableResult
    private static func shell(_ args: String...) -> Int32 {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = args
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }
}

// MARK: - Utilities

extension Data {
    var hexDescription: String {
        prefix(32).map { String(format: "%02x", $0) }.joined(separator: " ")
        + (count > 32 ? "..." : "")
    }
}

// MARK: - Quick start guide (printed at runtime)

func printQuickStart() {
    print("""
    ╔══════════════════════════════════════════════════════════════╗
    ║  Sony SED-E1 macOS Middleware — Quick Start                 ║
    ╠══════════════════════════════════════════════════════════════╣
    ║                                                              ║
    ║  PATH 1: ADB Socket Bridge (works TODAY, no RE needed)      ║
    ║  ─────────────────────────────────────────────────────────  ║
    ║  1. Plug Android phone (with glasses connected) via USB     ║
    ║  2. GlassesADBBridge.setupADBForward()                      ║
    ║  3. let bridge = GlassesADBBridge()                         ║
    ║     bridge.delegate = yourDelegate                          ║
    ║     bridge.connect()                                        ║
    ║                                                              ║
    ║  PATH 2: Direct BT SPP (needs protocol RE first)            ║
    ║  ─────────────────────────────────────────────────────────  ║
    ║  1. HCISnoop.enable() → pair glasses → do actions           ║
    ║  2. HCISnoop.pull() → open in Wireshark                     ║
    ║  3. Identify framing → fill in ProtocolFrame constants      ║
    ║  4. let bt = BluetoothGlassesConnection()                   ║
    ║     bt.connect(to: "XX:XX:XX:XX:XX:XX")  ← glasses MAC     ║
    ║                                                              ║
    ║  GET GLASSES MAC: read NFC tag on controller with any       ║
    ║  Android NFC app. NDEF record contains BT MAC address.      ║
    ╚══════════════════════════════════════════════════════════════╝
    """)
}
