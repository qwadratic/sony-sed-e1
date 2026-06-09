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
        AudioDemo(),
    ]
    
    private var menuIndex = 0
    var activeDemo: Demo?
    private var sensorSampleCount = 0
    private var frameAckCount = 0
    private var lastInputTime: Date = .distantPast
    
    // Onboarding state
    private var onboarding = true
    private var onboardingTapCount = 0
    private var logoX: Int = 0
    private var logoY: Int = 0
    
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
            Task {
                onboarding = true
                onboardingTapCount = 0
                await renderOnboarding()
            }
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
            if onboarding {
                await handleOnboardingInput(event)
                return
            }
            if let demo = activeDemo {
                switch event {
                case .tap:
                    await demo.onTap()
                case .swipeLeft, .swipeRight, .backButton:
                    if case .backButton = event {
                        await exitDemo()
                    } else {
                        await demo.onSwipe(event)
                    }
                default:
                    if let touchDemo = demo as? TouchDemo {
                        touchDemo.onTouchEvent(event)
                    }
                }
            } else {
                // At menu
                switch event {
                case .tap:
                    await enterDemo(menuIndex)
                case .jogRotateCCW:
                    menuIndex = (menuIndex - 1 + demos.count) % demos.count
                    await renderMenu()
                case .jogRotateCW:
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
            print("REPL: [0-8] demo, [t] tap, [m] menu, [d] debug level, [q] quit")
            while let line = readLine() {
                let cmd = line.trimmingCharacters(in: .whitespaces)
                Task {
                    switch cmd {
                    case "0"..."8":
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
                    case _ where cmd.hasPrefix("raw "):
                        // raw HEX send: "raw c3 00 01 01"
                        let hexStr = String(cmd.dropFirst(4))
                        let bytes = hexStr.split(separator: " ").compactMap { UInt8($0, radix: 16) }
                        if !bytes.isEmpty {
                            await self.glasses.transport.send(bytes, label: "RAW")
                            print("  → RAW [\(bytes.count)B] \(bytes.map{String(format:"%02x",$0)}.joined(separator:" "))")
                        }
                    case "ar":
                        // Quick AR mode test
                        print("Entering AR mode...")
                        await self.glasses.transport.send([0xc3, 0x00, 0x01, 0x01], label: "SetRenderMode(AR)")
                        print("  → AR mode set. Glasses should switch to AR rendering.")
                    case "normal":
                        // Back to normal mode
                        await self.glasses.transport.send([0xc3, 0x00, 0x01, 0x00], label: "SetRenderMode(NORMAL)")
                        print("  → Normal mode restored.")
                    default:
                        print("Unknown: \(cmd). [0-8] demo, [t] tap, [m] menu, [d] debug, [ar] AR mode, [raw XX] hex, [q] quit")
                    }
                }
            }
        }
    }

    // MARK: - Pi Logo Boot Screen
    
    // MARK: - Onboarding
    
    private func renderOnboarding() async {
        fb.clear()
        
        // Center logo initially
        logoX = (fb.width - 80) / 2
        logoY = (fb.height - 80) / 2 - 10
        drawPiLogo(at: logoX, logoY: logoY, size: 80)
        
        // Instruction text
        TextRenderer.drawText("Swipe the touch surface", x: 4, y: fb.height - 20, on: fb, value: 200)
        TextRenderer.drawText("Tap 3x to continue", x: 4, y: fb.height - 10, on: fb, value: 128)
        
        await glasses.display.show(fb.pixels)
    }
    
    private func handleOnboardingInput(_ event: InputEvent) async {
        switch event {
        case .tap:
            onboardingTapCount += 1
            print("  [onboarding] tap \(onboardingTapCount)/3")
            if onboardingTapCount >= 3 {
                onboarding = false
                print("  [onboarding] complete!")
                await renderMenu()
                return
            }
            // Redraw with tap count indicator
            fb.clear()
            drawPiLogo(at: logoX, logoY: logoY, size: 80)
            let dots = String(repeating: "*", count: onboardingTapCount) + String(repeating: ".", count: 3 - onboardingTapCount)
            TextRenderer.drawText("Tap [\(dots)]", x: 4, y: fb.height - 20, on: fb, value: 200)
            TextRenderer.drawText("\(3 - onboardingTapCount) more to start", x: 4, y: fb.height - 10, on: fb, value: 128)
            await glasses.display.show(fb.pixels)
            
        case .swipeLeft:
            logoX = max(0, logoX - 30)
            await redrawOnboarding()
        case .swipeRight:
            logoX = min(fb.width - 80, logoX + 30)
            await redrawOnboarding()
        case .fingerOn, .fingerOff:
            break  // ignore
        default:
            // Jog wheel moves logo too
            if case .jogRotateCW = event {
                logoX = min(fb.width - 80, logoX + 15)
                await redrawOnboarding()
            } else if case .jogRotateCCW = event {
                logoX = max(0, logoX - 15)
                await redrawOnboarding()
            }
        }
    }
    
    private func redrawOnboarding() async {
        fb.clear()
        drawPiLogo(at: logoX, logoY: logoY, size: 80)
        let dots = String(repeating: "*", count: onboardingTapCount) + String(repeating: ".", count: 3 - onboardingTapCount)
        TextRenderer.drawText("Swipe to move logo", x: 4, y: fb.height - 20, on: fb, value: 200)
        TextRenderer.drawText("Tap [\(dots)] \(3 - onboardingTapCount) more", x: 4, y: fb.height - 10, on: fb, value: 128)
        await glasses.display.show(fb.pixels)
    }
    
    /// Draw Pi logo into framebuffer without sending. Returns logo center + size.
    @discardableResult
    func drawPiLogo(at logoX: Int? = nil, logoY: Int? = nil, size: Int = 110) -> (x: Int, y: Int, size: Int) {
        // Pi favicon.svg: 800x800 viewBox, pixel-art staircase P + dot
        // SVG coords: 165.29, 282.65, 400, 517.36, 634.72 (unit=117.36)
        let logoSize = size
        let s = { (v: Double) -> Int in Int(v * Double(logoSize) / 800.0) }
        
        let ox = logoX ?? (fb.width - logoSize) / 2
        let oy = logoY ?? (fb.height - logoSize) / 2
        
        // P staircase — full brightness white on black
        // Top bar: (165,165) to (517,282)
        fb.fillRect(x: ox+s(165.29), y: oy+s(165.29), w: s(517.36)-s(165.29), h: s(282.65)-s(165.29), value: 255)
        // Left col row1: (165,282) to (282,400)
        fb.fillRect(x: ox+s(165.29), y: oy+s(282.65), w: s(282.65)-s(165.29), h: s(400)-s(282.65), value: 255)
        // Right arm row1: (400,282) to (517,400)
        fb.fillRect(x: ox+s(400), y: oy+s(282.65), w: s(517.36)-s(400), h: s(400)-s(282.65), value: 255)
        // Left col row2: (165,400) to (282,517)
        fb.fillRect(x: ox+s(165.29), y: oy+s(400), w: s(282.65)-s(165.29), h: s(517.36)-s(400), value: 255)
        // Left col row3: (165,517) to (282,634)
        fb.fillRect(x: ox+s(165.29), y: oy+s(517.36), w: s(282.65)-s(165.29), h: s(634.72)-s(517.36), value: 255)
        
        // Dot: (517,400) to (634,634)
        fb.fillRect(x: ox+s(517.36), y: oy+s(400), w: s(634.72)-s(517.36), h: s(634.72)-s(400), value: 255)
        
        return (ox, oy, logoSize)
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
