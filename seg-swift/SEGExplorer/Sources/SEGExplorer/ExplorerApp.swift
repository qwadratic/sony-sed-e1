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
    private var activeDemo: Demo?
    
    init() {
        glasses.delegate = self
    }
    
    func start() async {
        // For now, connect via local TCP (emulator)
        // In production: glasses.connectBluetooth()
        print("SEGExplorer ready. Demos: \(demos.count)")
        for (i, demo) in demos.enumerated() {
            print("  \(i): \(demo.name)")
        }
        await renderMenu()
    }
    
    // MARK: - GlassesDelegate
    
    func glasses(_ connection: GlassesConnection, didChangePhase phase: ConnectionPhase) {
        print("Phase: \(phase)")
    }
    
    func glasses(_ connection: GlassesConnection, didReceiveInput event: InputEvent) {
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
        Task {
            if let sensor = activeDemo as? SensorDemo {
                await sensor.updateSensorData(data)
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
    
    private func enterDemo(_ index: Int) async {
        guard index < demos.count else { return }
        let demo = demos[index]
        activeDemo = demo
        await demo.onEnter(glasses: glasses)
    }
    
    private func exitDemo() async {
        await activeDemo?.onExit()
        activeDemo = nil
        await renderMenu()
    }
}
