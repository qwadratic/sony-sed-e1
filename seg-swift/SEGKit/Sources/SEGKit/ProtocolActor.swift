import Foundation

/// Protocol state machine actor.
/// Routes decoded frames to correct subsystem. Extension apps never see this.
internal actor ProtocolActor {
    private enum Phase: Int {
        case waitProtocolVersion = 0
        case waitSettings = 1
        case waitVersion = 2
        case waitFota = 3
        case waitOpenApp = 4
        case ready = 5
    }
    
    private var phase: Phase = .waitProtocolVersion
    private let transport: TransportActor
    private let display: DisplaySubsystem
    private let camera: CameraSubsystem
    private let sensors: SensorSubsystem
    private let input: InputSubsystem
    
    weak var connection: GlassesConnection?
    
    init(transport: TransportActor,
         display: DisplaySubsystem,
         camera: CameraSubsystem,
         sensors: SensorSubsystem,
         input: InputSubsystem) {
        self.transport = transport
        self.display = display
        self.camera = camera
        self.sensors = sensors
        self.input = input
    }
    
    func setConnection(_ conn: GlassesConnection) {
        self.connection = conn
    }

    private var fotaTimeoutTask: Task<Void, Never>?

    func start() async {
        await transport.setFrameHandler { [weak self] frame in
            await self?.handle(frame)
        }
    }
    
    private func handle(_ frame: WireFrame) async {
        // Ignore 0x06 LevelNotification and 0xe5 LayoutEventNotify during handshake
        if phase != .ready && (frame.cmdId == 0x06 || frame.cmdId == 0xe5) {
            return
        }

        switch (phase, frame.cmdId) {
            
        // ── Handshake ────────────────────────────────────────
        case (.waitProtocolVersion, 0x0a):
            phase = .waitSettings
            await transport.send([0x71, 0x00, 0x00], label: "SettingsStatusReq")
            notifyPhase()
            
        case (.waitSettings, 0x72):
            phase = .waitVersion
            await transport.send([0x07, 0x00, 0x01, 0x01], label: "VersionReq")
            notifyPhase()
            
        case (.waitVersion, 0x08):
            phase = .waitFota
            await transport.send(
                [0x85, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00],
                label: "NewHostApp"
            )
            notifyPhase()
            // Start 5s timeout — emulator may never send FotaStatus
            fotaTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                await self?.fotaTimeout()
            }
            
        case (.waitFota, 0x81):
            fotaTimeoutTask?.cancel()
            await advanceToOpenApp()
            
        case (.waitOpenApp, 0x31):
            phase = .ready
            await display.initialize()
            notifyPhase()
            
        // ── Ready state routing ──────────────────────────────
        case (.ready, 0xe5), (.ready, 0x06):  // Input events
            if let event = input.parseEvent(cmdId: frame.cmdId, payload: frame.payload) {
                connection?.eventLog.log("INPUT", ["event": "\(event)"])
                connection?.delegate?.glasses(connection!, didReceiveInput: event)
            }
            
        case (.ready, 0xe8):  // Image ACK
            connection?.delegate?.glassesDidAcknowledgeFrame(connection!)
            
        case (.ready, 0xb5):  // Camera capture response
            camera.handleCaptureResponse(frame.payload)
            if let err = camera.lastError {
                connection?.delegate?.glasses(connection!, cameraError: err)
                camera.lastError = nil
            }
            
        case (.ready, 0xb6):  // Camera data chunk
            if let ack = camera.handleChunk(frame.payload) {
                await transport.send(ack, label: "CaptureDataAck")
            }
            
        case (.ready, 0xb7):  // Camera done
            if let jpeg = camera.handleDone(frame.payload) {
                connection?.eventLog.log("CAMERA", ["event": "captured", "bytes": jpeg.count])
                if camera.isMovieMode {
                    connection?.delegate?.glasses(connection!, didReceiveStreamFrame: jpeg, frameId: camera.streamFrameCount)
                } else {
                    connection?.delegate?.glasses(connection!, didCaptureJPEG: jpeg)
                }
            }
            
        case (.ready, 0x3a):  // Accelerometer
            let reading = sensors.handleAccelerometer(frame.payload)
            connection?.eventLog.log("SENSOR", [
                "accel_x": reading.accelerometer.x, "accel_y": reading.accelerometer.y, "accel_z": reading.accelerometer.z,
                "gyro_x": reading.gyroscope.x, "gyro_y": reading.gyroscope.y, "gyro_z": reading.gyroscope.z
            ])
            connection?.delegate?.glasses(connection!, didReceiveSensorData: reading)
            
        case (.ready, 0xbc):  // Gyroscope
            let reading = sensors.handleGyroscope(frame.payload)
            connection?.delegate?.glasses(connection!, didReceiveSensorData: reading)
            
        case (.ready, 0xbd):  // Magnetometer
            let reading = sensors.handleMagnetometer(frame.payload)
            connection?.delegate?.glasses(connection!, didReceiveSensorData: reading)
            
        case (.ready, 0x3b):  // Light sensor
            let reading = sensors.handleLight(frame.payload)
            connection?.delegate?.glasses(connection!, didReceiveSensorData: reading)
            
        case (.ready, 0x3e):  // BatterySensor data
            connection?.eventLog.debug("BatterySensor: \(frame.payload.map { String(format: "%02x", $0) }.joined(separator: " "))")
            
        case (.ready, 0xbb):  // Rotation vector
            let reading = sensors.handleAccelerometer(frame.payload)  // same SIMD3 format
            connection?.delegate?.glasses(connection!, didReceiveSensorData: reading)
            
        default:
            break  // Unknown or out-of-phase frame
        }
    }
    
    private func fotaTimeout() async {
        guard phase == .waitFota else { return }
        await advanceToOpenApp()
    }

    private func advanceToOpenApp() async {
        phase = .waitOpenApp
        await transport.send([0xff, 0x00, 0x00], label: "SyncResponse")
        await transport.send([0x30, 0x00, 0x00], label: "OpenAppStartReq")
        notifyPhase()
        // Emulator may not send 0x31 either — auto-advance after 3s
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.openAppTimeout()
        }
    }

    private func openAppTimeout() async {
        guard phase == .waitOpenApp else { return }
        phase = .ready
        await display.initialize()
        notifyPhase()
    }

    private func notifyPhase() {
        let cp: ConnectionPhase
        switch phase {
        case .waitProtocolVersion: cp = .connecting
        case .waitSettings, .waitVersion, .waitFota, .waitOpenApp:
            cp = .handshaking(step: phase.rawValue)
        case .ready: cp = .ready
        }
        connection?.phase = cp
        connection?.eventLog.log("PHASE", ["phase": "\(cp)", "step": phase.rawValue])
        connection?.delegate?.glasses(connection!, didChangePhase: cp)
    }
}
