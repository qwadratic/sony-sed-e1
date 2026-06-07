import Foundation
import zlib

/// Display API for extension apps.
/// Extension apps call show() with grayscale pixels. SDK handles encoding + transport.
public final class DisplaySubsystem: @unchecked Sendable {
    internal let transport: TransportActor
    internal var initialized = false
    
    internal init(transport: TransportActor) {
        self.transport = transport
    }
    
    /// Show 419×138 8-bit grayscale pixels on the glasses display.
    /// Each byte is 0 (black) to 255 (white). Array must be exactly 57822 bytes.
    public func show(_ grayscale: [UInt8]) async {
        guard grayscale.count == DisplayConstants.pixelCount else { return }
        guard initialized else { return }
        let cmd = Self.buildDisplayCommand(grayscale)
        await transport.send(cmd, label: "DisplayFrame")
    }
    
    /// Convert ARGB pixels to 8-bit grayscale using Sony's luma formula.
    /// Input: [R,G,B,A, R,G,B,A, ...] — 4 bytes per pixel, 419×138 pixels.
    public static func argbToGrayscale(_ argb: [UInt8]) -> [UInt8] {
        let pixelCount = DisplayConstants.pixelCount
        guard argb.count == pixelCount * 4 else { return [UInt8](repeating: 0, count: pixelCount) }
        var gray = [UInt8](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            let r = UInt32(argb[i * 4])
            let g = UInt32(argb[i * 4 + 1])
            let b = UInt32(argb[i * 4 + 2])
            let a = UInt32(argb[i * 4 + 3])
            let luma = (r * 299 + g * 587 + b * 114) / 1000
            gray[i] = UInt8((luma * a) / 255)
        }
        return gray
    }
    
    // MARK: - Internal
    
    internal func initialize() async {
        let layoutInit: [UInt8] = [
            0xe0, 0x00, 0x0a,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00
        ]
        await transport.send(layoutInit, label: "LayoutInit")
        initialized = true
    }
    
    internal static func buildDisplayCommand(_ grayscale: [UInt8]) -> [UInt8] {
        let compressed = deflateCompress(grayscale)
        
        // Sub1: PLACE_STATE (13 bytes)
        var sub1: [UInt8] = [0x01, 0x00, 0x0a]
        sub1 += [UInt8](repeating: 0, count: 10)
        
        // Sub2: PLACE_IMGOBJ (27 bytes)
        var sub2: [UInt8] = [0x03, 0x00, 0x18]
        sub2 += [0x00, 0x00, 0x00, 0x00]  // objId=0, layerId=0
        sub2 += [0x00, 0x00, 0x00, 0x00]  // x=0
        sub2 += [0x00, 0x00, 0x00, 0x00]  // y=0
        sub2 += [0x01, 0xa3]              // width=419
        sub2 += [0x00, 0x8a]              // height=138
        sub2 += [UInt8](repeating: 0, count: 8)
        
        // Sub3: IMG_DATA
        let imgLen = 2 + 1 + compressed.count
        var sub3: [UInt8] = [0x07, UInt8((imgLen >> 8) & 0xff), UInt8(imgLen & 0xff)]
        sub3 += [0x00, 0x00]  // objId=0
        sub3 += [0x01]        // imgFormat=1
        sub3 += compressed
        
        let totalPayload = sub1.count + sub2.count + sub3.count
        var cmd: [UInt8] = [
            0xe7,
            UInt8((totalPayload >> 8) & 0xff),
            UInt8(totalPayload & 0xff)
        ]
        cmd += sub1; cmd += sub2; cmd += sub3
        return cmd
    }
    
    internal static func deflateCompress(_ input: [UInt8]) -> [UInt8] {
        var mutableInput = input
        var output = [UInt8](repeating: 0, count: input.count + 256)
        var compressedSize = 0
        
        mutableInput.withUnsafeMutableBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                var stream = z_stream()
                stream.zalloc = nil; stream.zfree = nil; stream.opaque = nil
                deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED,
                              -15, 8, Z_DEFAULT_STRATEGY,
                              ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
                
                stream.next_in = inBuf.baseAddress!
                stream.avail_in = UInt32(inBuf.count)
                stream.next_out = outBuf.baseAddress!
                stream.avail_out = UInt32(outBuf.count)
                
                deflate(&stream, Z_FINISH)
                deflateEnd(&stream)
                
                compressedSize = outBuf.count - Int(stream.avail_out)
            }
        }
        
        return Array(output[0..<compressedSize])
    }
}
