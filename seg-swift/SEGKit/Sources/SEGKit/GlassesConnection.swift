import Foundation

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
    public func connectLocal(host: String, port: UInt16) async throws { }
    
    /// Disconnect and release all resources.
    public func disconnect() async { }
    
    public init() {
        let transport = TransportActor()
        let display = DisplaySubsystem(transport: transport)
        let camera = CameraSubsystem(transport: transport)
        let sensors = SensorSubsystem()
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
