import Foundation
import SEGKit

/// AR: Cylindrical — mock heading rotation with marker.
final class ARDemo: Demo {
    let name = "AR: Cylindrical"
    private var glasses: GlassesConnection?
    private let fb = FrameBuffer()
    private var heading: Double = 0
    private var rotationTask: Task<Void, Never>?
    
    func onEnter(glasses: GlassesConnection) async {
        self.glasses = glasses
        heading = 0
        
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                self.heading = self.heading.truncatingRemainder(dividingBy: 360) + 1
                await self.render()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
    
    func onTap() async {
        heading += 45
    }
    
    func onSwipe(_ direction: InputEvent) async {}
    
    func onExit() async {
        rotationTask?.cancel()
        glasses = nil
    }
    
    private func render() async {
        fb.clear()
        TextRenderer.drawText("AR MODE (simulated)", x: 4, y: 4, on: fb)
        TextRenderer.drawText(
            String(format: "Heading: %.0f deg", heading),
            x: 4, y: 22, on: fb
        )
        
        // Draw a marker cross that moves with heading
        let markerX = Int((heading / 360.0) * Double(fb.width)) % fb.width
        let markerY = 69  // center
        fb.drawLine(x0: markerX, y0: markerY - 15, x1: markerX, y1: markerY + 15)
        fb.drawLine(x0: markerX - 15, y0: markerY, x1: markerX + 15, y1: markerY)
        
        TextRenderer.drawText("[tap] +45 deg", x: 4, y: fb.height - 10, on: fb)
        await glasses?.display.show(fb.pixels)
    }
}
