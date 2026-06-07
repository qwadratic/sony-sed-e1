import SEGKit

/// Input: Touch — scrolling event log of all input events.
final class TouchDemo: Demo {
    let name = "Input: Touch"
    private var glasses: GlassesConnection?
    private let fb = FrameBuffer()
    private var log: [String] = []
    private let maxLines = 4
    
    func onEnter(glasses: GlassesConnection) async {
        self.glasses = glasses
        log = ["-- waiting for input --"]
        await render()
    }
    
    func onTap() async {
        addEvent("TAP")
    }
    
    func onSwipe(_ direction: InputEvent) async {
        switch direction {
        case .swipeLeft:  addEvent("SWIPE LEFT")
        case .swipeRight: addEvent("SWIPE RIGHT")
        
        
        default: break
        }
    }
    
    /// Called externally for touch press/release events.
    func onTouchEvent(_ event: InputEvent) {
        switch event {
        case .jogRotateCW: addEvent("JOG CW")
        case .jogRotateCCW: addEvent("JOG CCW")
        case .longPress: addEvent("LONG PRESS")
        default: break
        }
    }
    
    func onExit() async {
        log.removeAll()
        glasses = nil
    }
    
    private func addEvent(_ text: String) {
        log.insert(text, at: 0)
        if log.count > maxLines { log.removeLast() }
        Task { await render() }
    }
    
    private func render() async {
        fb.clear()
        TextRenderer.drawText("INPUT EVENTS", x: 4, y: 4, on: fb)
        fb.drawHLine(x: 0, y: 14, length: fb.width, value: 128)
        
        for (i, entry) in log.enumerated() {
            let y = 20 + i * 12
            TextRenderer.drawText("> \(entry)", x: 4, y: y, on: fb)
        }
        
        TextRenderer.drawText("tap/swipe/touch -> log", x: 4, y: fb.height - 10, on: fb)
        await glasses?.display.show(fb.pixels)
    }
}
