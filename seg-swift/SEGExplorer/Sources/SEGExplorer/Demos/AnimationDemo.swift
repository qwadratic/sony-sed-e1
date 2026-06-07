import SEGKit

/// Display: Animate — bouncing scan lines at ~15fps.
/// Demonstrates: continuous frame push, timer loop, pause/resume.
final class AnimationDemo: Demo {
    let name = "Display: Animate"
    private var glasses: GlassesConnection?
    private let fb = FrameBuffer()
    private var frameTask: Task<Void, Never>?
    private var paused = false
    private var scanY = 0
    private var frameCount = 0
    
    func onEnter(glasses: GlassesConnection) async {
        self.glasses = glasses
        paused = false
        scanY = 0
        frameCount = 0
        
        frameTask = Task { [weak self] in
            let start = ContinuousClock.now
            while !Task.isCancelled {
                guard let self, !self.paused else {
                    try? await Task.sleep(for: .milliseconds(66))
                    continue
                }
                self.fb.clear()
                
                // Scan line 1 (full brightness)
                self.fb.drawHLine(x: 0, y: self.scanY,
                                  length: self.fb.width, value: 255)
                
                // Scan line 2 (dim, offset by 69px)
                let y2 = (self.scanY + 69) % self.fb.height
                self.fb.drawHLine(x: 0, y: y2,
                                  length: self.fb.width, value: 80)
                
                // FPS counter
                self.frameCount += 1
                let elapsed = ContinuousClock.now - start
                let fps = Double(self.frameCount) / max(elapsed.durationSeconds, 0.001)
                TextRenderer.drawText(
                    String(format: "%.1f fps  frame %d", fps, self.frameCount),
                    x: 4, y: self.fb.height - 10, on: self.fb
                )
                
                await self.glasses?.display.show(self.fb.pixels)
                self.scanY = (self.scanY + 3) % self.fb.height
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }
    
    func onTap() async {
        paused.toggle()
        if paused {
            fb.clear()
            TextRenderer.drawText("PAUSED", x: 180, y: 60, on: fb)
            TextRenderer.drawText("[tap] resume", x: 160, y: 80, on: fb)
            await glasses?.display.show(fb.pixels)
        }
    }
    
    func onSwipe(_ direction: InputEvent) async {}
    
    func onExit() async {
        frameTask?.cancel()
        frameTask = nil
        glasses = nil
    }
}

extension Duration {
    /// Total seconds as a Double.
    var durationSeconds: Double {
        let (s, a) = components
        return Double(s) + Double(a) / 1_000_000_000_000
    }
}
