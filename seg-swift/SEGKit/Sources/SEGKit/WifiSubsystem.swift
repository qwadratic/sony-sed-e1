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
        guard !ssid.isEmpty else {
            print("  [wifi] No SSID configured")
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
        var channelMHz = detectWifiChannel()
        // SED-E1 only supports 802.11b/g/n 2.4GHz — if Mac is on 5GHz,
        // scan for 2.4GHz channel of the same SSID, or default to strongest 2.4GHz.
        if channelMHz > 3000 {
            let ch24 = detect24GHzChannel(ssid: ssid)
            print("  [wifi] Mac on 5GHz (\(channelMHz)MHz) — using 2.4GHz \(ch24)MHz for glasses")
            channelMHz = ch24
        }
        // Send 0 to let glasses auto-detect channel (firmware may ignore our hint)
        print("  [wifi] Sending freq=0 (auto) + hint=\(channelMHz)MHz")
        let autoFreq = 0  // Let glasses scan all 2.4GHz channels
        let psk = derivePSK(ssid: ssid, passphrase: passphrase)
        guard !psk.isEmpty else {
            print("  [wifi] PSK derivation failed")
            return false
        }

        let req = buildWifiConnectReq(ssid: ssid, passphrase: passphrase, psk: psk,
                                       hostIP: ip, port: serverPort, channelMHz: autoFreq)
        state = .connecting
        await transport.send(req, label: "WifiConnectReq")

        // Wait for TCP accept (glasses connect to our server)
        for _ in 0..<300 {  // 60 seconds max
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
        // No [weak self] — WifiSubsystem lives as long as GlassesConnection, no retain cycle risk.
        // Using strong ref ensures state transitions complete even if accept takes a while.
        DispatchQueue.global(qos: .userInitiated).async {
            var clientAddr = sockaddr_in()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(fd, $0, &addrLen)
                }
            }
            guard clientFd >= 0 else {
                let err = errno
                print("  [wifi] TCP accept failed: errno=\(err) (\(String(cString: strerror(err))))")
                return
            }
            
            // Log client IP
            let clientIP = "\(clientAddr.sin_addr.s_addr & 0xFF).\((clientAddr.sin_addr.s_addr >> 8) & 0xFF).\((clientAddr.sin_addr.s_addr >> 16) & 0xFF).\((clientAddr.sin_addr.s_addr >> 24) & 0xFF)"
            print("  [wifi] Glasses TCP connected! fd=\(clientFd) from \(clientIP)")
            
            // Enable TCP keepalive to prevent connection dropping
            var one: Int32 = 1
            Darwin.setsockopt(clientFd, SOL_SOCKET, SO_KEEPALIVE, &one, socklen_t(MemoryLayout<Int32>.size))
            // Disable Nagle for low latency
            Darwin.setsockopt(clientFd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
            
            // Set state SYNCHRONOUSLY before any async work — the upgrade() polling loop
            // checks this from another thread, so it must be visible immediately.
            self.state = .connected
            
            Task {
                await transport.setWiFiClient(clientFd)
            }

            // WiFi read loop
            var buf = [UInt8](repeating: 0, count: 8192)
            while true {
                let n = Darwin.read(clientFd, &buf, buf.count)
                if n <= 0 {
                    if n < 0 {
                        let err = errno
                        print("  [wifi] TCP read error: errno=\(err) (\(String(cString: strerror(err))))")
                    } else {
                        print("  [wifi] TCP connection closed by glasses (EOF)")
                    }
                    break
                }
                let data = Data(buf[0..<n])
                Task { await transport.receiveTCP(data) }
            }
            print("  [wifi] WiFi TCP connection closed, fd=\(clientFd)")
            Darwin.close(clientFd)
            self.state = .off
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
                                       hostIP: String, port: Int, channelMHz: Int) -> [UInt8] {
        // 184-byte payload layout (from DEX bytecode analysis):
        // 0x00-0x1F: SSID (32 bytes, null-padded)
        // 0x20-0x3F: Passphrase (32 bytes, null-padded)
        // 0x40-0x5F: Reserved (zeros)
        // 0x60-0x63: goAddr (WiFi Direct GO IP — zeros for infrastructure mode)
        // 0x64-0x67: staAddr (TCP server IP — glasses connect HERE)
        // 0x68-0x6B: subnetMask
        // 0x6C-0x6F: gateway (same as staAddr for simple networks)
        // 0x70-0x73: dnsServer (can be zeros)
        // 0x74-0x75: frequency in MHz (big-endian)
        // 0x76-0x77: TCP port (big-endian)
        // 0x78-0xB7: PSK as 64-char hex string
        var payload = [UInt8](repeating: 0, count: 184)
        
        let ssidB = Array(ssid.utf8.prefix(32))
        for i in 0..<ssidB.count { payload[i] = ssidB[i] }
        
        let passB = Array(passphrase.utf8.prefix(32))
        for i in 0..<passB.count { payload[0x20 + i] = passB[i] }
        
        let octets = hostIP.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return [] }
        
        // 0x60: goAddr = zeros (infrastructure mode, not WiFi Direct)
        // 0x64: staAddr = our TCP server IP (REQUIRED — glasses TCP-connect here)
        for i in 0..<4 { payload[0x64 + i] = octets[i] }
        
        // 0x68: subnet mask
        payload[0x68] = 255; payload[0x69] = 255; payload[0x6A] = 255; payload[0x6B] = 0
        
        // 0x6C: gateway = same as host IP
        for i in 0..<4 { payload[0x6C + i] = octets[i] }
        
        // 0x74: frequency
        payload[0x74] = UInt8((channelMHz >> 8) & 0xFF)
        payload[0x75] = UInt8(channelMHz & 0xFF)
        
        // 0x76: TCP port
        payload[0x76] = UInt8((port >> 8) & 0xFF)
        payload[0x77] = UInt8(port & 0xFF)
        
        // 0x78: PSK as 64-char hex string
        let pskB = Array(psk.utf8.prefix(64))
        for i in 0..<pskB.count { payload[0x78 + i] = pskB[i] }
        
        print("  [wifi] ConnectReq: ssid=\(ssid) staAddr=\(hostIP):\(port) freq=\(channelMHz)MHz psk=\(psk.prefix(8))...")
        return [0x94, 0x00, 0xB8] + payload
    }

    internal func detectWifiChannel() -> Int {
        // Try system_profiler (works without special permissions)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPAirPortDataType"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        // Parse "Channel: 40 (5GHz, 80MHz)" or "Channel: 6 (2GHz, 20MHz)"
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Channel:") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let ch = Int(parts[1]) {
                    let freq = channelToFrequency(ch)
                    print("  [wifi] Detected channel \(ch) → \(freq) MHz")
                    return freq
                }
            }
        }
        
        // Fallback: try airport tool
        let proc2 = Process()
        proc2.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc2.arguments = ["bash", "-c",
            "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/channel:/{print $2}' | head -1"]
        let pipe2 = Pipe()
        proc2.standardOutput = pipe2
        proc2.standardError = FileHandle.nullDevice
        try? proc2.run(); proc2.waitUntilExit()
        let raw = String(data: pipe2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chStr = raw.split(separator: ",").first.flatMap(String.init) ?? raw
        if let ch = Int(chStr) {
            let freq = channelToFrequency(ch)
            print("  [wifi] Airport channel \(ch) → \(freq) MHz")
            return freq
        }
        
        print("  [wifi] Channel detection failed, defaulting to 2437 MHz (ch6)")
        return 2437
    }
    
    private func channelToFrequency(_ channel: Int) -> Int {
        // 2.4 GHz band: channels 1-14
        if channel >= 1 && channel <= 14 {
            return 2407 + channel * 5
        }
        // 5 GHz band: channels 36-165
        if channel >= 36 && channel <= 165 {
            return 5000 + channel * 5
        }
        return 2437 // fallback ch6
    }
    
    /// Scan for strongest 2.4GHz network matching SSID, or any 2.4GHz channel.
    private func detect24GHzChannel(ssid: String) -> Int {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPAirPortDataType"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        // Parse all visible 2.4GHz networks and their channels
        var best24Channel = 6  // default
        var bestSignal = -999
        var lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for i in 0..<lines.count {
            if lines[i].hasPrefix("Channel:") && lines[i].contains("2GHz") {
                // Extract channel number
                let parts = lines[i].split(separator: " ")
                guard parts.count >= 2, let ch = Int(parts[1]) else { continue }
                
                // Look for signal strength nearby
                var signal = -80 // default if not found
                for j in max(0, i-3)...min(lines.count-1, i+3) {
                    if lines[j].hasPrefix("Signal / Noise:") {
                        // "Signal / Noise: -49 dBm / -85 dBm"
                        let sigParts = lines[j].split(separator: " ")
                        if sigParts.count >= 4, let s = Int(sigParts[3]) {
                            signal = s
                        }
                        break
                    }
                }
                
                if signal > bestSignal {
                    bestSignal = signal
                    best24Channel = ch
                }
            }
        }
        
        let freq = channelToFrequency(best24Channel)
        print("  [wifi] Best 2.4GHz: channel \(best24Channel) (\(freq)MHz) signal=\(bestSignal)dBm")
        return freq
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
