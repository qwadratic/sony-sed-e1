import SEGKit

/// Display: Text — cycles font sizes on tap.
/// Demonstrates: display.show(), tap handling.
/// Equivalent of Sony's TextDemo.java.
final class TextDemo: Demo {
    let name = "Display: Text"
    private var glasses: GlassesConnection?
    private let fb = FrameBuffer()
    private var sizeIndex = 0
    private let sizes = [1, 2]  // scale factors for 5×7 font
    
    func onEnter(glasses: GlassesConnection) async {
        self.glasses = glasses
        await render()
    }
    
    func onTap() async {
        sizeIndex = (sizeIndex + 1) % sizes.count
        await render()
    }
    
    func onSwipe(_ direction: InputEvent) async {}
    func onExit() async { glasses = nil }
    
    private func render() async {
        fb.clear()
        let scale = sizes[sizeIndex]
        let title = "TEXT DEMO (scale \(scale)x)"
        TextRenderer.drawText(title, x: 4, y: 4, on: fb)
        
        // Draw separator
        fb.drawHLine(x: 0, y: 14, length: fb.width, value: 128)
        
        // Alphabet
        TextRenderer.drawText("ABCDEFGHIJKLMNOPQRSTUVWXYZ", x: 4, y: 20, on: fb)
        TextRenderer.drawText("abcdefghijklmnopqrstuvwxyz", x: 4, y: 32, on: fb)
        TextRenderer.drawText("0123456789 !@#$%^&*()", x: 4, y: 44, on: fb)
        
        // Footer
        TextRenderer.drawText("[tap] cycle size", x: 4, y: fb.height - 10, on: fb)
        
        await glasses?.display.show(fb.pixels)
    }
}
