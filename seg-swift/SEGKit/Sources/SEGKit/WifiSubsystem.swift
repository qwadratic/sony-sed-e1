import Foundation

/// WiFi upgrade subsystem. Handles BT→WiFi transport switch.
public final class WifiSubsystem: @unchecked Sendable {
    internal let transport: TransportActor

    /// WiFi credentials. Set before calling upgrade().
    public var ssid: String = ""
    public var passphrase: String = ""

    /// Current WiFi state.
    public enum WifiState: Sendable {
        case off, turningOn, enabled, connecting, connected, switching, active
    }
    public internal(set) var state: WifiState = .off

    internal var serverFd: Int32 = -1
    internal var serverPort: Int = 0

    internal init(transport: TransportActor) {
        self.transport = transport
    }

    /// Full WiFi upgrade sequence. Returns true if WiFi path is now active.
    public func upgrade() async -> Bool {
        guard !ssid.isEmpty, !passphrase.isEmpty else {
            print("  [wifi] No SSID/passphrase configured")
            return false
        }
        guard let ip = getInterfaceIP("en0") else {
            print("  [wifi] No en0 IP — not connected to WiFi?")
            return false
        }

        // Step 1: Turn on WiFi radio
        state = .turningOn
        await transport.send([0x92, 0x00, 0x00], label: "WifiTurnOnReq")

        // Wait for 0x91 ENABLED — handled by ProtocolActor setting state
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(200))
            if state == .enabled { break }
        }
        guard state == .enabled else {
            print("  [wifi] WiFi radio did not enable (timeout)")
            return false
        }

        // Step 2: Create TCP server
        serverPort = createTCPServer()
        guard serverPort > 0 else { return false }

        // Step 3: Start accept in background
        startAccept(ip: ip)

        // Step 4: Derive PSK + build ConnectReq
        let channelMHz = detectWifiChannel()
        let psk = derivePSK(ssid: ssid, passphrase: passphrase)
        guard !psk.isEmpty else {
            print("  [wifi] PSK derivation failed")
            return false
        }

        let req = buildWifiConnectReq(ssid: ssid, passphrase: passphrase, psk: psk,
                                       goIP: ip, port: serverPort, channelMHz: channelMHz)
        state = .connecting
        await transport.send(req, label: "WifiConnectReq")

        // Wait for TCP accept (glasses connect to our server)
        for _ in 0..<150 {  // 30 seconds max
            try? await Task.sleep(for: .milliseconds(200))
            if state == .connected { break }
        }
        guard state == .connected else {
            print("  [wifi] Glasses did not connect via TCP (timeout)")
            return false
        }

        // Step 5: Switch data path to WiFi
        state = .switching
        await transport.send([0x96, 0x00, 0x01, 0x01], label: "WifiDPSwitchPathReq(WIFI)")

        // Wait for 0x97
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(200))
            if state == .active { break }
        }

        return state == .active
    }

    // MARK: - Internal helpers

    internal func createTCPServer() -> Int {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var one: Int32 = 1
        Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = 0  // INADDR_ANY
        addr.sin_port = 0         // OS assigns

        let bindRet = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRet == 0 else { Darwin.close(fd); return -1 }
        guard Darwin.listen(fd, 1) == 0 else { Darwin.close(fd); return -1 }

        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(fd, $0, &addrLen)
            }
        }
        let port = Int(UInt16(bigEndian: addr.sin_port))
        serverFd = fd
        print("  [wifi] TCP server listening on port \(port)")
        return port
    }

    internal func startAccept(ip: String) {
        let fd = serverFd
        let transport = self.transport
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let clientFd = Darwin.accept(fd, nil, nil)
            guard clientFd >= 0 else { return }
            print("  [wifi] Glasses TCP connected! fd=\(clientFd)")

            Task {
                await transport.setWiFiClient(clientFd)
                self?.state = .connected
            }

            // WiFi read loop
            var buf = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = Darwin.read(clientFd, &buf, buf.count)
                if n <= 0 { break }
                let data = Data(buf[0..<n])
                Task { await transport.receiveTCP(data) }
            }
            print("  [wifi] WiFi TCP connection closed")
            self?.state = .off
        }
    }

    internal func derivePSK(ssid: String, passphrase: String) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        let script = "import hashlib,sys; psk=hashlib.pbkdf2_hmac('sha1',sys.argv[2].encode(),sys.argv[1].encode(),4096,32); print(psk.hex())"
        proc.arguments = ["-c", script, ssid, passphrase]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    internal func buildWifiConnectReq(ssid: String, passphrase: String, psk: String,
                                       goIP: String, port: Int, channelMHz: Int) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: 184)
        let ssidB = Array(ssid.utf8.prefix(32))
        for i in 0..<ssidB.count { payload[i] = ssidB[i] }
        let passB = Array(passphrase.utf8.prefix(32))
        for i in 0..<passB.count { payload[0x20 + i] = passB[i] }
        let octets = goIP.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return [] }
        for i in 0..<4 { payload[0x60 + i] = octets[i] }
        payload[0x68] = 255; payload[0x69] = 255; payload[0x6A] = 255; payload[0x6B] = 0
        payload[0x74] = UInt8((channelMHz >> 8) & 0xFF); payload[0x75] = UInt8(channelMHz & 0xFF)
        payload[0x76] = UInt8((port >> 8) & 0xFF); payload[0x77] = UInt8(port & 0xFF)
        let pskB = Array(psk.utf8.prefix(64))
        for i in 0..<pskB.count { payload[0x78 + i] = pskB[i] }
        return [0x94, 0x00, 0xB8] + payload
    }

    internal func detectWifiChannel() -> Int {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["bash", "-c",
            "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/channel:/{print $2}' | head -1"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()
        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chStr = raw.split(separator: ",").first.flatMap(String.init) ?? raw
        if let ch = Int(chStr), ch >= 1, ch <= 14 { return 2407 + ch * 5 }
        return 2437  // default ch6
    }
}

// Helper — get IP address for a network interface
private func getInterfaceIP(_ iface: String) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
    proc.arguments = ["getifaddr", iface]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    guard (try? proc.run()) != nil else { return nil }
    proc.waitUntilExit()
    let ip = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let parts = ip.split(separator: ".")
    guard parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) else { return nil }
    return ip
}
