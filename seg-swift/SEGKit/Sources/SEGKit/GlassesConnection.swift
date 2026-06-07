import Foundation
import IOBluetooth

/// Errors from connection setup.
public enum ConnectionError: Error, Sendable {
    case socketFailed
    case invalidAddress
    case connectFailed(errno: Int32)
    case alreadyConnected
    case deviceNotFound
}

/// Connection state observable by extension apps.
public enum ConnectionPhase: Sendable {
    case disconnected
    case connecting
    case handshaking(step: Int)  // 0-4
    case ready
}

/// High-level glasses connection. Extension apps use this — never wire protocol.
public final class GlassesConnection: @unchecked Sendable {
    public let display: DisplaySubsystem
    public let camera: CameraSubsystem
    public let sensors: SensorSubsystem
    public let input: InputSubsystem
    
    public weak var delegate: GlassesDelegate?
    
    public internal(set) var phase: ConnectionPhase = .disconnected
    
    // Internal actors — NOT public
    internal let transport: TransportActor
    internal let protocol_sm: ProtocolActor
    
    /// Strong reference to keep the BT bridge alive during connection.
    private var btBridge: BluetoothBridge?
    
    /// Connect via Bluetooth (scan for SmartEyeglass device).
    /// - Parameter address: Optional BT address. If nil, scans paired devices.
    public func connectBluetooth(address: String? = nil) async throws {
        phase = .connecting
        delegate?.glasses(self, didChangePhase: .connecting)

        // Find SmartEyeglass device
        let targetAddress: String
        if let addr = address {
            targetAddress = addr
        } else {
            guard let found = Self.scanForSmartEyeglass() else {
                throw ConnectionError.deviceNotFound
            }
            targetAddress = found
        }

        guard let device = IOBluetoothDevice(addressString: targetAddress) else {
            throw ConnectionError.invalidAddress
        }

        // SDP query to find RFCOMM channel — must run on main RunLoop
        device.performSDPQuery(nil)
        // Wait for SDP query to complete (IOBluetooth posts results async)
        try await Task.sleep(for: .seconds(4))

        var rfcommChannelID: BluetoothRFCOMMChannelID = 0
        if let services = device.services as? [IOBluetoothSDPServiceRecord] {
            for svc in services {
                var ch: BluetoothRFCOMMChannelID = 0
                if svc.getRFCOMMChannelID(&ch) == kIOReturnSuccess {
                    rfcommChannelID = ch
                    break
                }
            }
        }
        if rfcommChannelID == 0 { rfcommChannelID = 1 } // fallback

        // Set up bridge
        let bridge = BluetoothBridge(transport: transport)
        self.btBridge = bridge  // strong ref

        // Wire protocol actor
        await protocol_sm.setConnection(self)
        await protocol_sm.start()

        // Open RFCOMM channel
        var channel: IOBluetoothRFCOMMChannel? = nil
        let result = device.openRFCOMMChannelAsync(
            &channel,
            withChannelID: rfcommChannelID,
            delegate: bridge
        )

        guard result == kIOReturnSuccess else {
            self.btBridge = nil
            throw ConnectionError.connectFailed(errno: result)
        }

        // Set up connection/disconnection handlers
        bridge.onConnected = {
            // Channel is now open — handshake begins automatically
            // when glasses send ProtocolVersion (0x0a)
        }

        bridge.onDisconnected = { [weak self] in
            guard let self else { return }
            self.phase = .disconnected
            self.delegate?.glasses(self, didChangePhase: .disconnected)
        }

        bridge.onError = { [weak self] err in
            guard let self else { return }
            self.phase = .disconnected
            self.delegate?.glasses(self, didChangePhase: .disconnected)
        }
    }
    
    /// Connect via TCP to ADB-forwarded emulator socket.
    public func connectLocal(host: String, port: UInt16) async throws {
        phase = .connecting
        delegate?.glasses(self, didChangePhase: .connecting)

        // Create TCP socket
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ConnectionError.socketFailed }

        // Connect
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            Darwin.close(fd)
            throw ConnectionError.invalidAddress
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            throw ConnectionError.connectFailed(errno: errno)
        }

        // Store fd in transport
        await transport.setLocalFd(fd)

        // Set up protocol actor
        await protocol_sm.setConnection(self)
        await protocol_sm.start()

        // Start TCP read loop on background thread
        let transport = self.transport
        DispatchQueue.global(qos: .userInitiated).async {
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = Darwin.read(fd, &buf, buf.count)
                if n <= 0 { break }
                let data = Data(buf[0..<n])
                Task {
                    await transport.receiveTCP(data)
                }
            }
        }
    }
    
    /// Disconnect and release all resources.
    public func disconnect() async {
        btBridge = nil  // release BT delegate
        await transport.closeAll()
        phase = .disconnected
        delegate?.glasses(self, didChangePhase: .disconnected)
    }

    // MARK: - Device scanning

    /// Scan paired devices for SmartEyeglass. Returns BT address or nil.
    public static func scanForSmartEyeglass() -> String? {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }

        // First pass: look for "SmartEyeglass" in name
        for d in devices {
            let name = (d.name ?? "").lowercased()
            if name.contains("smarteyeglass") || name.contains("sed-e1") {
                return d.addressString
            }
        }

        // Second pass: check for saved last-used address
        let lastUsedPath = NSString("~/.glasses_last_addr").expandingTildeInPath
        if let saved = try? String(contentsOfFile: lastUsedPath, encoding: .utf8)
                              .trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty {
            return saved
        }

        return nil
    }

    /// List all paired Bluetooth devices. Returns [(name, address)].
    public static func listPairedDevices() -> [(name: String, address: String)] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        return devices.compactMap { d in
            guard let addr = d.addressString else { return nil }
            return (name: d.name ?? "(unknown)", address: addr)
        }
    }
    
    public init() {
        let transport = TransportActor()
        let display = DisplaySubsystem(transport: transport)
        let camera = CameraSubsystem(transport: transport)
        let sensors = SensorSubsystem(transport: transport)
        let input = InputSubsystem()
        
        self.transport = transport
        self.display = display
        self.camera = camera
        self.sensors = sensors
        self.input = input
        self.protocol_sm = ProtocolActor(
            transport: transport,
            display: display,
            camera: camera,
            sensors: sensors,
            input: input
        )
    }
}
