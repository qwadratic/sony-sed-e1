import Foundation

/// Extension apps implement this to receive glasses events.
/// Equivalent of Sony's SmartEyeglassEventListener.
public protocol GlassesDelegate: AnyObject, Sendable {
    /// Connection phase changed.
    func glasses(_ connection: GlassesConnection, didChangePhase phase: ConnectionPhase)
    
    /// Display acknowledged a frame.
    func glassesDidAcknowledgeFrame(_ connection: GlassesConnection)
    
    /// Camera JPEG captured (still mode).
    func glasses(_ connection: GlassesConnection, didCaptureJPEG data: Data)
    
    /// Camera stream frame received.
    func glasses(_ connection: GlassesConnection, didReceiveStreamFrame data: Data, frameId: Int)
    
    /// Camera error occurred.
    func glasses(_ connection: GlassesConnection, cameraError code: Int)
    
    /// Sensor data received.
    func glasses(_ connection: GlassesConnection, didReceiveSensorData data: SensorReading)
    
    /// Touch/tap/swipe input from glasses.
    func glasses(_ connection: GlassesConnection, didReceiveInput event: InputEvent)
}

/// Default implementations — all optional.
public extension GlassesDelegate {
    func glasses(_ connection: GlassesConnection, didChangePhase phase: ConnectionPhase) {}
    func glassesDidAcknowledgeFrame(_ connection: GlassesConnection) {}
    func glasses(_ connection: GlassesConnection, didCaptureJPEG data: Data) {}
    func glasses(_ connection: GlassesConnection, didReceiveStreamFrame data: Data, frameId: Int) {}
    func glasses(_ connection: GlassesConnection, cameraError code: Int) {}
    func glasses(_ connection: GlassesConnection, didReceiveSensorData data: SensorReading) {}
    func glasses(_ connection: GlassesConnection, didReceiveInput event: InputEvent) {}
}
