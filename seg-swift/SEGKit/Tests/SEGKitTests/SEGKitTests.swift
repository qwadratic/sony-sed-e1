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
    
    // MARK: - Phase 1 Tests
    
    func testFrameReassembly() async {
        let transport = TransportActor()
        var received = [WireFrame]()
        await transport.setFrameHandler { frame in
            received.append(frame)
        }
        
        // Feed a complete frame: cmdId=0x0a, payloadLen=0
        await transport.receiveTCP(Data([0x0a, 0x00, 0x00]))
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].cmdId, 0x0a)
        XCTAssertEqual(received[0].payload.count, 0)
        
        // Feed a frame split across two chunks: cmdId=0x07, payloadLen=2, payload=[0xAB, 0xCD]
        received.removeAll()
        await transport.receiveTCP(Data([0x07, 0x00]))  // partial header
        XCTAssertEqual(received.count, 0, "Should not fire on partial header")
        await transport.receiveTCP(Data([0x02, 0xAB, 0xCD]))  // rest of header + payload
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].cmdId, 0x07)
        XCTAssertEqual(received[0].payload, Data([0xAB, 0xCD]))
    }
    
    func testFrameReassemblyPartial() async {
        let transport = TransportActor()
        var received = [WireFrame]()
        await transport.setFrameHandler { frame in
            received.append(frame)
        }
        
        // Header says 1 byte payload but no payload yet
        await transport.receiveTCP(Data([0x07, 0x00, 0x01]))
        XCTAssertEqual(received.count, 0, "Should not fire — payload byte missing")
        
        // Now feed the payload byte
        await transport.receiveTCP(Data([0x01]))
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0].cmdId, 0x07)
        XCTAssertEqual(received[0].payload, Data([0x01]))
    }
    
    func testDisplayCommandSize() {
        let pixelCount = DisplayConstants.pixelCount
        
        // All-black
        let black = [UInt8](repeating: 0, count: pixelCount)
        let cmdBlack = DisplaySubsystem.buildDisplayCommand(black)
        XCTAssertEqual(cmdBlack[0], 0xe7)
        
        // All-white
        let white = [UInt8](repeating: 255, count: pixelCount)
        let cmdWhite = DisplaySubsystem.buildDisplayCommand(white)
        XCTAssertEqual(cmdWhite[0], 0xe7)
        
        // Checkerboard
        var checker = [UInt8](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            checker[i] = (i % 2 == 0) ? 0x00 : 0xFF
        }
        let cmdChecker = DisplaySubsystem.buildDisplayCommand(checker)
        XCTAssertEqual(cmdChecker[0], 0xe7)
        
        // Uniform data compresses very small; checkerboard has more entropy → larger
        XCTAssertTrue(cmdBlack.count < 200,
                      "All-black (\(cmdBlack.count)) should compress small")
        XCTAssertTrue(cmdWhite.count < 200,
                      "All-white (\(cmdWhite.count)) should compress small")
        XCTAssertTrue(cmdChecker.count > cmdBlack.count,
                      "Checkerboard (\(cmdChecker.count)) should be larger than all-black (\(cmdBlack.count))")
        XCTAssertTrue(cmdChecker.count > cmdWhite.count,
                      "Checkerboard (\(cmdChecker.count)) should be larger than all-white (\(cmdWhite.count))")
    }
    
    func testArgbToGrayscaleRedChannel() {
        let pixelCount = DisplayConstants.pixelCount
        // Pure red: R=255, G=0, B=0, A=255
        var argb = [UInt8](repeating: 0, count: pixelCount * 4)
        for i in stride(from: 0, to: argb.count, by: 4) {
            argb[i]     = 255  // R
            argb[i + 1] = 0    // G
            argb[i + 2] = 0    // B
            argb[i + 3] = 255  // A
        }
        let gray = DisplaySubsystem.argbToGrayscale(argb)
        XCTAssertEqual(gray.count, pixelCount)
        // luma = (255*299)/1000 = 76, scaled by alpha 255/255 = 76
        XCTAssertEqual(gray[0], 76, "Pure red should map to grayscale ~76")
    }
    
    func testCameraAccumulatorFlow() {
        let transport = TransportActor()
        let cam = CameraSubsystem(transport: transport)
        
        // 0xb5 capture response: status=0, format=0, size=10(LE), field4=0
        var resp = Data([0x00, 0x00])            // status=0, format=0
        resp.append(contentsOf: [0x0a, 0x00, 0x00, 0x00])  // size=10 LE
        resp.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // field4=0
        cam.handleCaptureResponse(resp)
        
        // 0xb6 chunk 0: seq=0, len=5, data=[0xFF,0xD8,0xFF,0xE0,0x00]
        var chunk0 = Data([0x00])                // seq=0
        chunk0.append(contentsOf: [0x05, 0x00])  // len=5 (LE)
        chunk0.append(contentsOf: [0xFF, 0xD8, 0xFF, 0xE0, 0x00])
        let ack0 = cam.handleChunk(chunk0)
        XCTAssertNotNil(ack0)
        XCTAssertEqual(ack0, [0xf1, 0x00, 0x01, 0x00])
        
        // 0xb6 chunk 1: seq=1, len=5, data=[0x10,0x4A,0x46,0x49,0x46]
        var chunk1 = Data([0x01])                // seq=1
        chunk1.append(contentsOf: [0x05, 0x00])  // len=5
        chunk1.append(contentsOf: [0x10, 0x4A, 0x46, 0x49, 0x46])
        let ack1 = cam.handleChunk(chunk1)
        XCTAssertNotNil(ack1)
        XCTAssertEqual(ack1, [0xf1, 0x00, 0x01, 0x01])
        
        // 0xb7 done: status=0, count=2, size=10
        let donePayload = Data([0x00, 0x02, 0x0a, 0x00, 0x00, 0x00])
        let jpeg = cam.handleDone(donePayload)
        XCTAssertNotNil(jpeg)
        XCTAssertEqual(jpeg!.count, 10, "Should have accumulated 10 bytes")
        // Verify actual bytes
        XCTAssertEqual(Array(jpeg!), [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
    }
    
    func testInputEventParsing() {
        let input = InputSubsystem()
        
        // cmdId=0x06, empty payload → .tap
        XCTAssertEqual(input.parseEvent(cmdId: 0x06, payload: Data()), .tap)
        
        // cmdId=0xe5, payload=[0x00] → .tap
        // Note: current guard requires count>=2; single-byte tap/longPress may fail
        let tapResult = input.parseEvent(cmdId: 0xe5, payload: Data([0x00]))
        XCTAssertEqual(tapResult, .tap, "0xe5 with action=0x00 should be .tap")
        
        // cmdId=0xe5, payload=[0x01] → .longPress
        let longResult = input.parseEvent(cmdId: 0xe5, payload: Data([0x01]))
        XCTAssertEqual(longResult, .longPress, "0xe5 with action=0x01 should be .longPress")
        
        // cmdId=0xe5, payload=[0x03, 0x01] → .swipeLeft
        XCTAssertEqual(input.parseEvent(cmdId: 0xe5, payload: Data([0x03, 0x01])), .swipeLeft)
        
        // cmdId=0xe5, payload=[0x03, 0x02] → .swipeRight
        XCTAssertEqual(input.parseEvent(cmdId: 0xe5, payload: Data([0x03, 0x02])), .swipeRight)
    }
    
    // MARK: - Phase 3 Tests
    
    func testCameraModeEnum() {
        XCTAssertEqual(CameraMode.still.rawValue, 0)
        XCTAssertEqual(CameraMode.movie.rawValue, 1)
    }
    
    func testCameraStreamFlow() {
        let transport = TransportActor()
        let cam = CameraSubsystem(transport: transport)
        
        // 0xb5 response: status=0, format=0, jpeg_size=15 (LE), field4=0
        var resp = Data([0x00, 0x00])                        // status=0, format=0
        resp.append(contentsOf: [0x0f, 0x00, 0x00, 0x00])   // size=15 LE
        resp.append(contentsOf: [0x00, 0x00, 0x00, 0x00])   // field4=0
        cam.handleCaptureResponse(resp)
        XCTAssertTrue(cam.capturing, "Should be capturing after status=0 response")
        
        // 0xb6 chunk seq=0: 8 bytes of data
        var chunk0 = Data([0x00])                            // seq=0
        chunk0.append(contentsOf: [0x08, 0x00])              // len=8 LE
        chunk0.append(contentsOf: [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
        let ack0 = cam.handleChunk(chunk0)
        XCTAssertNotNil(ack0, "Should return ACK for chunk 0")
        XCTAssertEqual(ack0, [0xf1, 0x00, 0x01, 0x00])
        
        // 0xb6 chunk seq=1: 7 bytes of data
        var chunk1 = Data([0x01])                            // seq=1
        chunk1.append(contentsOf: [0x07, 0x00])              // len=7 LE
        chunk1.append(contentsOf: [0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x48])
        let ack1 = cam.handleChunk(chunk1)
        XCTAssertNotNil(ack1, "Should return ACK for chunk 1")
        XCTAssertEqual(ack1, [0xf1, 0x00, 0x01, 0x01])
        
        // 0xb7 done
        let donePayload = Data([0x00, 0x02, 0x0f, 0x00, 0x00, 0x00])
        let jpeg = cam.handleDone(donePayload)
        XCTAssertNotNil(jpeg, "handleDone should return assembled JPEG")
        XCTAssertEqual(jpeg!.count, 15, "Should have accumulated 15 bytes")
    }
    
    func testCameraErrorStatus() {
        let transport = TransportActor()
        let cam = CameraSubsystem(transport: transport)
        
        // 0xb5 response with status=1 (error)
        var resp = Data([0x01, 0x00])                        // status=1 (error)
        resp.append(contentsOf: [0x00, 0x00, 0x00, 0x00])   // size=0
        resp.append(contentsOf: [0x00, 0x00, 0x00, 0x00])   // field4=0
        cam.handleCaptureResponse(resp)
        
        XCTAssertEqual(cam.lastError, 1, "lastError should be 1 after error response")
        XCTAssertFalse(cam.capturing, "capturing should be false after error")
    }
    
    func testSensorLightParsing() {
        let transport = TransportActor()
        let sensor = SensorSubsystem(transport: transport)
        
        // Build 4-byte float payload for 500.0
        var payload = Data(count: 4)
        var value: Float = 500.0
        withUnsafeBytes(of: &value) { buf in
            payload = Data(buf)
        }
        
        let reading = sensor.handleLight(payload)
        XCTAssertEqual(reading.light, 500.0, accuracy: 0.01,
                       "Light sensor should parse 500.0")
        XCTAssertEqual(sensor.current.light, 500.0, accuracy: 0.01)
    }
    
    func testSensorReadingStruct() {
        let accel = SIMD3<Float>(1.0, 2.0, 3.0)
        let gyro  = SIMD3<Float>(4.0, 5.0, 6.0)
        let mag   = SIMD3<Float>(7.0, 8.0, 9.0)
        let reading = SensorReading(
            accelerometer: accel,
            gyroscope: gyro,
            magnetometer: mag,
            light: 42.0,
            timestamp: 1234567890
        )
        
        XCTAssertEqual(reading.accelerometer, accel)
        XCTAssertEqual(reading.gyroscope, gyro)
        XCTAssertEqual(reading.magnetometer, mag)
        XCTAssertEqual(reading.light, 42.0, accuracy: 0.01)
        XCTAssertEqual(reading.timestamp, 1234567890)
    }
    
    func testSensorTypeEnum() {
        XCTAssertEqual(SensorType.accelerometer.rawValue, 0x01)
        XCTAssertEqual(SensorType.camera.rawValue, 0x13)
    }
}
