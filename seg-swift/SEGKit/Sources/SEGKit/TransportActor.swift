import Foundation
import IOBluetooth

/// Wire frame parsed from transport.
internal struct WireFrame: Sendable {
    let cmdId: UInt8
    let payload: Data
}

/// Transport actor — owns BT + WiFi + Local TCP connections.
/// Each transport has its OWN reassembly buffer (actor-isolated).
internal actor TransportActor {
    private var btRxBuf = Data()
    private var wifiRxBuf = Data()
    private var localFd: Int32 = -1
    private var wifiClientFd: Int32 = -1
    private var wifiActive = false
    private var btChannel: IOBluetoothRFCOMMChannel?
    
    private var frameHandler: ((WireFrame) async -> Void)?
    
    func setFrameHandler(_ handler: @escaping (WireFrame) async -> Void) {
        self.frameHandler = handler
    }
    
    /// Receive raw bytes from BT RFCOMM callback.
    func receiveBT(_ data: Data) async {
        btRxBuf.append(data)
        btRxBuf = await drainFrames(buffer: btRxBuf)
    }
    
    /// Receive raw bytes from WiFi/Local TCP.
    func receiveTCP(_ data: Data) async {
        wifiRxBuf.append(data)
        wifiRxBuf = await drainFrames(buffer: wifiRxBuf)
    }
    
    /// Send bytes over the primary transport.
    func send(_ bytes: [UInt8], label: String) {
        let data = Data(bytes)
        if wifiActive || localFd >= 0 {
            let fd = localFd >= 0 ? localFd : wifiClientFd
            guard fd >= 0 else { return }
            data.withUnsafeBytes { buf in
                _ = Darwin.write(fd, buf.baseAddress!, buf.count)
            }
        } else if let ch = btChannel {
            let mtu = Int(ch.getMTU())
            let chunkSize = mtu > 0 ? mtu : 665
            var offset = 0
            while offset < bytes.count {
                let end = min(offset + chunkSize, bytes.count)
                var chunk = Array(bytes[offset..<end])
                ch.writeSync(&chunk, length: UInt16(chunk.count))
                offset = end
            }
        }
    }
    
    func setBluetoothChannel(_ ch: IOBluetoothRFCOMMChannel) {
        btChannel = ch
    }
    
    func setLocalFd(_ fd: Int32) {
        localFd = fd
        wifiActive = false  // local mode doesn't need wifi flag
    }
    
    func setWiFiClient(_ fd: Int32) {
        wifiClientFd = fd
        wifiActive = true
    }

    func closeAll() {
        if localFd >= 0 { Darwin.close(localFd); localFd = -1 }
        if wifiClientFd >= 0 { Darwin.close(wifiClientFd); wifiClientFd = -1 }
        _ = btChannel?.close()
        btChannel = nil
        wifiActive = false
        btRxBuf = Data()
        wifiRxBuf = Data()
    }
    
    // MARK: - Private
    
    private func drainFrames(buffer: Data) async -> Data {
        var buf = buffer
        while buf.count >= 3 {
            let len = (Int(buf[1]) << 8) | Int(buf[2])
            let total = 3 + len
            guard buf.count >= total else { break }
            let frame = WireFrame(
                cmdId: buf[0],
                payload: Data(buf[3..<total])
            )
            buf = Data(buf[total...])
            await frameHandler?(frame)
        }
        return buf
    }
}
