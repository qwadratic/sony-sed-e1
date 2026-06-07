import Foundation
import SEGKit

/// Camera: Still — tap to capture a JPEG.
final class CameraCaptureDemo: Demo {
    let name = "Camera: Still"
    private var glasses: GlassesConnection?
    private let fb = FrameBuffer()
    private var captureCount = 0
    
    func onEnter(glasses: GlassesConnection) async {
        self.glasses = glasses
        captureCount = 0
        fb.clear()
        TextRenderer.drawText("CAMERA STILL", x: 4, y: 4, on: fb)
        TextRenderer.drawText("[tap] capture", x: 4, y: fb.height - 10, on: fb)
        await glasses.display.show(fb.pixels)
    }
    
    func onTap() async {
        fb.clear()
        TextRenderer.drawText("Capturing...", x: 4, y: 60, on: fb)
        await glasses?.display.show(fb.pixels)
        await glasses?.camera.captureStill(resolution: .qvga, quality: .fine)
    }
    
    func onSwipe(_ direction: InputEvent) async {}
    
    func onExit() async {
        await glasses?.camera.stop()
        glasses = nil
    }
    
    /// Called by app controller when JPEG arrives via GlassesDelegate.
    func onCaptureReceived(_ data: Data) async {
        captureCount += 1
        fb.clear()
        TextRenderer.drawText("Capture #\(captureCount) OK", x: 4, y: 30, on: fb)
        TextRenderer.drawText("Size: \(data.count) bytes", x: 4, y: 46, on: fb)
        TextRenderer.drawText("[tap] capture again", x: 4, y: fb.height - 10, on: fb)
        await glasses?.display.show(fb.pixels)
    }
}
