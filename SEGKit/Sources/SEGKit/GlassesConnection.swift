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
    public let wifi: WifiSubsystem
    public let eventLog = EventLogger()
    
    public weak var delegate: GlassesDelegate?
    
    public internal(set) var phase: ConnectionPhase = .disconnected
    
    // Internal actors — NOT public
    // Public for raw wire access (advanced/debug use)
    public let transport: TransportActor
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
            // Collect all RFCOMM channels
            var channels: [BluetoothRFCOMMChannelID] = []
            for svc in services {
                var ch: BluetoothRFCOMMChannelID = 0
                if svc.getRFCOMMChannelID(&ch) == kIOReturnSuccess {
                    channels.append(ch)
                }
            }
            eventLog.debug("SDP found RFCOMM channels: \(channels)", minLevel: .normal)
            // Prefer channel 4 (SmartEyeglass SPP data channel)
            // Skip channel 1 (HFP) and channel 7 (unknown/control)
            if channels.contains(4) {
                rfcommChannelID = 4
            } else if let first = channels.first(where: { $0 != 1 }) {
                rfcommChannelID = first
            } else if let first = channels.first {
                rfcommChannelID = first
            }
        }
        if rfcommChannelID == 0 { rfcommChannelID = 4 } // SmartEyeglass default
        eventLog.debug("Using RFCOMM channel \(rfcommChannelID)", minLevel: .normal)

        // Set up bridge
        let bridge = BluetoothBridge(transport: transport)
        bridge.eventLog = eventLog
        self.btBridge = bridge  // strong ref

        // Wire protocol actor BEFORE opening channel
        await protocol_sm.setConnection(self)
        await protocol_sm.start()

        // Set up connection/disconnection handlers BEFORE opening channel
        bridge.onConnected = { [weak self] in
            self?.eventLog.debug("🟢 RFCOMM channel open callback fired", minLevel: .normal)
            self?.attemptWifiUpgrade()
        }

        bridge.onDisconnected = { [weak self] in
            guard let self else { return }
            self.eventLog.debug("🔴 RFCOMM channel closed", minLevel: .normal)
            self.phase = .disconnected
            self.delegate?.glasses(self, didChangePhase: .disconnected)
        }

        bridge.onError = { [weak self] err in
            guard let self else { return }
            self.eventLog.debug("❌ RFCOMM error: \(err)", minLevel: .normal)
            self.phase = .disconnected
            self.delegate?.glasses(self, didChangePhase: .disconnected)
        }

        // Open RFCOMM channel via bridge (ensures main thread dispatch)
        let result = bridge.openChannel(device: device, channelID: rfcommChannelID)

        guard result == kIOReturnSuccess else {
            self.btBridge = nil
            throw ConnectionError.connectFailed(errno: result)
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

    /// Paired device info with signal strength for online detection.
    public struct PairedDevice {
        public let name: String
        public let address: String
        public let rssi: Int        // 0 = not broadcasting, negative = signal (closer to 0 = stronger)
        public let isGlasses: Bool  // class 7/5 = Wearable/Glasses
        public let isConnected: Bool
        
        /// Device appears to be powered on and nearby.
        public var isOnline: Bool { rssi < 0 }
    }

    /// List all paired Bluetooth devices with signal strength.
    /// Sorted: online glasses first (by signal strength), then other online, then offline.
    public static func listPairedDevices() -> [PairedDevice] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        var result = devices.compactMap { d -> PairedDevice? in
            guard let addr = d.addressString else { return nil }
            let name = d.name ?? "(unknown)"
            let rssi = Int(d.rawRSSI())
            let isGlasses = d.deviceClassMajor == 7 && d.deviceClassMinor == 5
            return PairedDevice(
                name: name, address: addr, rssi: rssi,
                isGlasses: isGlasses, isConnected: d.isConnected()
            )
        }
        // Sort: online glasses (strongest first) → online others → offline
        result.sort { a, b in
            if a.isGlasses != b.isGlasses { return a.isGlasses }
            if a.isOnline != b.isOnline { return a.isOnline }
            if a.isOnline && b.isOnline { return a.rssi > b.rssi } // closer to 0 = stronger
            return false
        }
        return result
    }
    
    /// Load WiFi credentials from a .env file (SSID=... PSWD=...)
    public func loadWifiCredentials(from path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "SSID": wifi.ssid = val
            case "PSWD": wifi.passphrase = val
            default: break
            }
        }
    }

    /// Attempt WiFi upgrade after BT handshake. Call after phase=ready.
    internal func attemptWifiUpgrade() {
        guard !wifi.ssid.isEmpty else { return }
        Task {
            // Wait for phase=ready
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(200))
                if case .ready = phase { break }
            }
            guard case .ready = phase else { return }

            eventLog.debug("Attempting WiFi upgrade...", minLevel: .normal)
            let success = await wifi.upgrade()
            if success {
                eventLog.debug("WiFi upgrade successful — data path active", minLevel: .normal)
            } else {
                eventLog.debug("WiFi upgrade failed — staying on BT", minLevel: .normal)
            }
        }
    }

    public init() {
        let transport = TransportActor()
        let display = DisplaySubsystem(transport: transport)
        let camera = CameraSubsystem(transport: transport)
        let sensors = SensorSubsystem(transport: transport)
        let input = InputSubsystem()
        let wifi = WifiSubsystem(transport: transport)
        
        self.transport = transport
        self.display = display
        self.camera = camera
        self.sensors = sensors
        self.input = input
        self.wifi = wifi
        self.protocol_sm = ProtocolActor(
            transport: transport,
            display: display,
            camera: camera,
            sensors: sensors,
            input: input
        )
        
        // Wire event log to transport so TX/RX are logged
        Task { await transport.setEventLog(eventLog) }
    }
}
