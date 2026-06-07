import XCTest
@testable import SEGKit

final class SEGKitTests: XCTestCase {
    func testDisplayCommandBuild() {
        let black = [UInt8](repeating: 0, count: DisplayConstants.pixelCount)
        let cmd = DisplaySubsystem.buildDisplayCommand(black)
        XCTAssertEqual(cmd[0], 0xe7)
        XCTAssertTrue(cmd.count > 40)  // header + compressed
        XCTAssertTrue(cmd.count < 200) // all-black compresses very small
    }
    
    func testArgbToGrayscale() {
        // Pure white pixel: R=255, G=255, B=255, A=255 → luma=255
        var argb = [UInt8](repeating: 0, count: DisplayConstants.pixelCount * 4)
        for i in stride(from: 0, to: argb.count, by: 4) {
            argb[i] = 255; argb[i+1] = 255; argb[i+2] = 255; argb[i+3] = 255
        }
        let gray = DisplaySubsystem.argbToGrayscale(argb)
        XCTAssertEqual(gray.count, DisplayConstants.pixelCount)
        XCTAssertEqual(gray[0], 255)
    }
    
    func testDeflateCompress() {
        let input = [UInt8](repeating: 0, count: 57822)
        let compressed = DisplaySubsystem.deflateCompress(input)
        XCTAssertTrue(compressed.count < 200)
        XCTAssertTrue(compressed.count > 0)
    }
    
    func testInputParseTap() {
        let input = InputSubsystem()
        let event = input.parseEvent(cmdId: 0x06, payload: Data())
        XCTAssertEqual(event, .tap)
    }
    
    func testCameraChunkDedup() {
        let transport = TransportActor()
        let cam = CameraSubsystem(transport: transport)
        
        // Simulate capture response
        var resp = Data([0x00, 0x00])  // status=0, format=0
        resp.append(contentsOf: [0x64, 0x00, 0x00, 0x00])  // 100 bytes
        resp.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // field4
        cam.handleCaptureResponse(resp)
        
        // Chunk 0
        var chunk0 = Data([0x00])  // seq=0
        chunk0.append(contentsOf: [0x05, 0x00])  // len=5
        chunk0.append(contentsOf: [0xFF, 0xD8, 0xFF, 0xE0, 0x00])  // JPEG start
        let ack0 = cam.handleChunk(chunk0)
        XCTAssertNotNil(ack0)
        XCTAssertEqual(ack0?[0], 0xf1)
        
        // Duplicate chunk 0 — should be ignored
        let ack0dup = cam.handleChunk(chunk0)
        XCTAssertNotNil(ack0dup)  // ACK sent but data not accumulated
    }
}
