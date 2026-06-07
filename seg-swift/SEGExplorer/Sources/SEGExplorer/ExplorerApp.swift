import Foundation
import SEGKit

/// Main explorer app — menu + demo routing.
/// Equivalent of Sony's ExplorerControl.java.
final class ExplorerApp: GlassesDelegate, @unchecked Sendable {
    let glasses = GlassesConnection()
    private let fb = FrameBuffer()
    
    private let demos: [Demo] = [
        TextDemo(),
        AnimationDemo(),
        GraphicsDemo(),
        TouchDemo(),
        SensorDemo(),
        CameraCaptureDemo(),
        CameraStreamDemo(),
        ARDemo(),
    ]
    
    private var menuIndex = 0
    var activeDemo: Demo?
    private var sensorSampleCount = 0
    private var frameAckCount = 0
    private var lastInputTime: Date = .distantPast
    
    init() {
        glasses.delegate = self
    }
    
    func start() async {
        print("SEGExplorer ready. Demos: \(demos.count)")
        for (i, demo) in demos.enumerated() {
            print("  \(i): \(demo.name)")
        }
        // Menu renders when phase becomes .ready
        startREPL()
    }
    
    // MARK: - GlassesDelegate
    
    func glasses(_ connection: GlassesConnection, didChangePhase phase: ConnectionPhase) {
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[\(ts)] PHASE: \(phase)")
        if case .ready = phase {
            Task { await renderMenu() }
        }
    }
    
    func glasses(_ connection: GlassesConnection, didReceiveInput event: InputEvent) {
        // Debounce: ignore events within 200ms of each other
        let now = Date()
        guard now.timeIntervalSince(lastInputTime) > 0.2 else { return }
        lastInputTime = now
        let ts = ISO8601DateFormatter().string(from: now)
        print("[\(ts)] INPUT: \(event)")
        Task {
            if let demo = activeDemo {
                switch event {
                case .tap:
                    await demo.onTap()
                case .swipeLeft, .swipeRight, .swipeUp, .swipeDown:
                    if case .swipeDown = event {
                        // Swipe down exits demo
                        await exitDemo()
                    } else {
                        await demo.onSwipe(event)
                    }
                default:
                    // Route touch events to TouchDemo if applicable
                    if let touchDemo = demo as? TouchDemo {
                        touchDemo.onTouchEvent(event)
                    }
                }
            } else {
                // At menu
                switch event {
                case .tap:
                    await enterDemo(menuIndex)
                case .swipeUp:
                    menuIndex = (menuIndex - 1 + demos.count) % demos.count
                    await renderMenu()
                case .swipeDown:
                    menuIndex = (menuIndex + 1) % demos.count
                    await renderMenu()
                default: break
                }
            }
        }
    }
    
    func glasses(_ connection: GlassesConnection, didCaptureJPEG data: Data) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let path = "/tmp/seg-capture-\(Int(Date().timeIntervalSince1970)).jpg"
        try? data.write(to: URL(fileURLWithPath: path))
        print("[\(ts)] CAMERA: captured \(data.count) bytes → \(path)")
        let isJPEG = data.count > 2 && data[0] == 0xFF && data[1] == 0xD8
        print("  JPEG valid: \(isJPEG), first bytes: \(data.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "))")
        Task {
            if let cam = activeDemo as? CameraCaptureDemo {
                await cam.onCaptureReceived(data)
            }
        }
    }
    
    func glasses(_ connection: GlassesConnection,
                 didReceiveStreamFrame data: Data, frameId: Int) {
        Task {
            if let stream = activeDemo as? CameraStreamDemo {
                await stream.onStreamFrame(data)
            }
        }
    }
    
    func glasses(_ connection: GlassesConnection,
                 didReceiveSensorData data: SensorReading) {
        sensorSampleCount += 1
        if sensorSampleCount % 10 == 0 {
            print(String(format: "[SENSOR #%d] accel=(%.2f, %.2f, %.2f) gyro=(%.3f, %.3f, %.3f) mag=(%.1f, %.1f, %.1f)",
                         sensorSampleCount,
                         data.accelerometer.x, data.accelerometer.y, data.accelerometer.z,
                         data.gyroscope.x, data.gyroscope.y, data.gyroscope.z,
                         data.magnetometer.x, data.magnetometer.y, data.magnetometer.z))
        }
        Task {
            if let sensor = activeDemo as? SensorDemo {
                await sensor.updateSensorData(data)
            }
        }
    }

    func glassesDidAcknowledgeFrame(_ connection: GlassesConnection) {
        frameAckCount += 1
        if frameAckCount % 50 == 0 {
            print("[DISPLAY] \(frameAckCount) frames acknowledged")
        }
    }
    
    // MARK: - REPL

    private let logLevels: [LogLevel] = [.silent, .normal, .verbose, .debug]
    private var logLevelIndex = 1  // start at .normal

    func startREPL() {
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            print("REPL: [0-7] demo, [t] tap, [m] menu, [d] debug level, [q] quit")
            while let line = readLine() {
                let cmd = line.trimmingCharacters(in: .whitespaces)
                Task {
                    switch cmd {
                    case "0"..."7":
                        if let idx = Int(cmd) {
                            if self.activeDemo != nil { await self.exitDemo() }
                            await self.enterDemo(idx)
                        }
                    case "t":
                        await self.activeDemo?.onTap()
                    case "m":
                        await self.exitDemo()
                    case "d":
                        self.logLevelIndex = (self.logLevelIndex + 1) % self.logLevels.count
                        let newLevel = self.logLevels[self.logLevelIndex]
                        self.glasses.eventLog.level = newLevel
                        print("\n─── Log level: \(newLevel) ───\n")
                    case "q":
                        await self.glasses.disconnect()
                        exit(0)
                    default:
                        print("Unknown: \(cmd). [0-7] demo, [t] tap, [m] menu, [d] debug, [q] quit")
                    }
                }
            }
        }
    }

    // MARK: - Menu
    
    private func renderMenu() async {
        fb.clear()
        TextRenderer.drawText("SEG EXPLORER", x: 4, y: 4, on: fb)
        fb.drawHLine(x: 0, y: 14, length: fb.width, value: 128)
        
        let visibleCount = 4
        let startIdx = max(0, min(menuIndex - 1, demos.count - visibleCount))
        
        for i in 0..<visibleCount {
            let idx = startIdx + i
            guard idx < demos.count else { break }
            let y = 20 + i * 14
            let prefix = idx == menuIndex ? "> " : "  "
            let value: UInt8 = idx == menuIndex ? 255 : 128
            TextRenderer.drawText("\(prefix)\(demos[idx].name)",
                                  x: 4, y: y, on: fb, value: value)
        }
        
        TextRenderer.drawText(
            "[tap] select  [swipe] navigate  \(menuIndex+1)/\(demos.count)",
            x: 4, y: fb.height - 10, on: fb
        )
        await glasses.display.show(fb.pixels)
    }
    
    func enterDemo(_ index: Int) async {
        guard index < demos.count else { return }
        let demo = demos[index]
        activeDemo = demo
        await demo.onEnter(glasses: glasses)
    }
    
    func exitDemo() async {
        await activeDemo?.onExit()
        activeDemo = nil
        await renderMenu()
    }
}
