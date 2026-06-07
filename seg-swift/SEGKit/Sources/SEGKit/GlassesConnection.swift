import Foundation

/// Errors from connection setup.
public enum ConnectionError: Error, Sendable {
    case socketFailed
    case invalidAddress
    case connectFailed(errno: Int32)
    case alreadyConnected
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
    
    /// Connect via Bluetooth (scan for SmartEyeglass device).
    public func connectBluetooth() async throws { }
    
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
        await transport.closeAll()
        phase = .disconnected
        delegate?.glasses(self, didChangePhase: .disconnected)
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
