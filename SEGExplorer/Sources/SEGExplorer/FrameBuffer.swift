import SEGKit

/// Simple 419×138 framebuffer for drawing on the glasses display.
/// Replaces Android's Bitmap+Canvas for the monochrome display.
public final class FrameBuffer {
    public let width = DisplayConstants.width    // 419
    public let height = DisplayConstants.height   // 138
    public private(set) var pixels: [UInt8]       // 57822 bytes, 8-bit grayscale
    
    public init() {
        pixels = [UInt8](repeating: 0, count: DisplayConstants.pixelCount)
    }
    
    /// Clear to black.
    public func clear() {
        pixels = [UInt8](repeating: 0, count: DisplayConstants.pixelCount)
    }
    
    /// Fill entire buffer with a value.
    public func fill(_ value: UInt8) {
        pixels = [UInt8](repeating: value, count: DisplayConstants.pixelCount)
    }
    
    /// Set a single pixel. Origin is top-left.
    public func setPixel(x: Int, y: Int, value: UInt8) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        pixels[y * width + x] = value
    }
    
    /// Get a pixel value.
    public func getPixel(x: Int, y: Int) -> UInt8 {
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        return pixels[y * width + x]
    }
    
    /// Draw a horizontal line.
    public func drawHLine(x: Int, y: Int, length: Int, value: UInt8 = 255) {
        for dx in 0..<length {
            setPixel(x: x + dx, y: y, value: value)
        }
    }
    
    /// Draw a vertical line.
    public func drawVLine(x: Int, y: Int, length: Int, value: UInt8 = 255) {
        for dy in 0..<length {
            setPixel(x: x, y: y + dy, value: value)
        }
    }
    
    /// Draw a rectangle outline.
    public func drawRect(x: Int, y: Int, w: Int, h: Int, value: UInt8 = 255) {
        drawHLine(x: x, y: y, length: w, value: value)
        drawHLine(x: x, y: y + h - 1, length: w, value: value)
        drawVLine(x: x, y: y, length: h, value: value)
        drawVLine(x: x + w - 1, y: y, length: h, value: value)
    }
    
    /// Fill a rectangle.
    public func fillRect(x: Int, y: Int, w: Int, h: Int, value: UInt8 = 255) {
        for dy in 0..<h {
            for dx in 0..<w {
                setPixel(x: x + dx, y: y + dy, value: value)
            }
        }
    }
    
    /// Draw a line using Bresenham's algorithm.
    public func drawLine(x0: Int, y0: Int, x1: Int, y1: Int, value: UInt8 = 255) {
        var x = x0, y = y0
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            setPixel(x: x, y: y, value: value)
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }
    
    /// Draw a circle outline using midpoint algorithm.
    public func drawCircle(cx: Int, cy: Int, r: Int, value: UInt8 = 255) {
        var x = r, y = 0, err = 1 - r
        while x >= y {
            setPixel(x: cx + x, y: cy + y, value: value)
            setPixel(x: cx + y, y: cy + x, value: value)
            setPixel(x: cx - y, y: cy + x, value: value)
            setPixel(x: cx - x, y: cy + y, value: value)
            setPixel(x: cx - x, y: cy - y, value: value)
            setPixel(x: cx - y, y: cy - x, value: value)
            setPixel(x: cx + y, y: cy - x, value: value)
            setPixel(x: cx + x, y: cy - y, value: value)
            y += 1
            if err < 0 { err += 2 * y + 1 }
            else { x -= 1; err += 2 * (y - x) + 1 }
        }
    }
}
