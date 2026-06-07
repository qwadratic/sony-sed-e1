import Foundation
import SEGKit

/// Camera: Stream — continuous JPEG streaming.
final class CameraStreamDemo: Demo {
    let name = "Camera: Stream"
    private var glasses: GlassesConnection?
    private let fb = FrameBuffer()
    private var streaming = false
    private var frameCount = 0
    private var startTime: ContinuousClock.Instant?
    
    func onEnter(glasses: GlassesConnection) async {
        self.glasses = glasses
        streaming = false
        frameCount = 0
        fb.clear()
        TextRenderer.drawText("CAMERA STREAM", x: 4, y: 4, on: fb)
        TextRenderer.drawText("[tap] start", x: 4, y: fb.height - 10, on: fb)
        await glasses.display.show(fb.pixels)
    }
    
    func onTap() async {
        if !streaming {
            streaming = true
            frameCount = 0
            startTime = .now
            await glasses?.camera.startStream(resolution: .qvga)
        } else {
            streaming = false
            await glasses?.camera.stop()
            fb.clear()
            TextRenderer.drawText("Stopped. Total: \(frameCount) frames", x: 4, y: 60, on: fb)
            TextRenderer.drawText("[tap] restart", x: 4, y: fb.height - 10, on: fb)
            await glasses?.display.show(fb.pixels)
        }
    }
    
    func onSwipe(_ direction: InputEvent) async {}
    
    func onExit() async {
        if streaming { await glasses?.camera.stop() }
        glasses = nil
    }
    
    /// Called on each stream frame.
    func onStreamFrame(_ data: Data) async {
        guard streaming else { return }
        frameCount += 1
        let elapsed = (ContinuousClock.now - (startTime ?? .now)).durationSeconds
        let fps = Double(frameCount) / max(elapsed, 0.001)
        fb.clear()
        TextRenderer.drawText("STREAM LIVE", x: 4, y: 4, on: fb)
        TextRenderer.drawText(
            String(format: "frame #%d  %.1f fps  %dB", frameCount, fps, data.count),
            x: 4, y: 30, on: fb
        )
        TextRenderer.drawText("[tap] stop", x: 4, y: fb.height - 10, on: fb)
        await glasses?.display.show(fb.pixels)
    }
}
