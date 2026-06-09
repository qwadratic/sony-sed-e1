import Foundation
import SEGKit

/// Display: Graphics — shapes catalog + rotating wireframe cube.
final class GraphicsDemo: Demo {
    let name = "Display: Graphics"
    private var glasses: GlassesConnection?
    private let fb = FrameBuffer()
    private var cubeMode = false
    private var cubeTask: Task<Void, Never>?
    private var angle: Double = 0
    
    func onEnter(glasses: GlassesConnection) async {
        self.glasses = glasses
        cubeMode = false
        await renderShapes()
    }
    
    func onTap() async {
        cubeMode.toggle()
        if cubeMode {
            cubeTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { break }
                    self.angle += 0.05
                    await self.renderCube()
                    try? await Task.sleep(for: .milliseconds(66))
                }
            }
        } else {
            cubeTask?.cancel()
            cubeTask = nil
            await renderShapes()
        }
    }
    
    func onSwipe(_ direction: InputEvent) async {}
    
    func onExit() async {
        cubeTask?.cancel()
        glasses = nil
    }
    
    private func renderShapes() async {
        fb.clear()
        TextRenderer.drawText("GRAPHICS  [tap] cube", x: 4, y: 4, on: fb)
        fb.drawRect(x: 10, y: 20, w: 60, h: 40)
        fb.fillRect(x: 80, y: 20, w: 60, h: 40, value: 128)
        fb.drawCircle(cx: 200, cy: 50, r: 25)
        fb.drawCircle(cx: 260, cy: 50, r: 15)
        fb.drawLine(x0: 300, y0: 20, x1: 380, y1: 70)
        fb.drawLine(x0: 300, y0: 70, x1: 380, y1: 20)
        await glasses?.display.show(fb.pixels)
    }
    
    private func renderCube() async {
        fb.clear()
        // 8 vertices of unit cube centered at origin
        let verts: [(Double, Double, Double)] = [
            (-1,-1,-1), (1,-1,-1), (1,1,-1), (-1,1,-1),
            (-1,-1, 1), (1,-1, 1), (1,1, 1), (-1,1, 1)
        ]
        let edges = [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]
        
        let cosA = cos(angle), sinA = sin(angle)
        let cosB = cos(angle * 0.7), sinB = sin(angle * 0.7)
        
        // Project 3D → 2D
        let projected: [(Int, Int)] = verts.map { (x, y, z) in
            // Rotate Y axis
            let rx = x * cosA - z * sinA
            let rz = x * sinA + z * cosA
            // Rotate X axis
            let ry = y * cosB - rz * sinB
            let rz2 = y * sinB + rz * cosB
            // Perspective
            let d = 1.0 + rz2 * 0.3
            let px = Int(rx / d * 40 + 209)  // center X
            let py = Int(ry / d * 40 + 69)   // center Y
            return (px, py)
        }
        
        for (a, b) in edges {
            fb.drawLine(x0: projected[a].0, y0: projected[a].1,
                       x1: projected[b].0, y1: projected[b].1)
        }
        
        TextRenderer.drawText("[tap] shapes", x: 4, y: fb.height - 10, on: fb)
        await glasses?.display.show(fb.pixels)
    }
}
