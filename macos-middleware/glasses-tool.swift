#!/usr/bin/env swift
/**
 glasses-tool.swift
 Sony SED-E1 macOS direct connection tool

 Modes:
   scan    — discover nearby BT devices (power on glasses first)
   pair    — interactively pair glasses by address
   connect — open RFCOMM SPP channel, dump all bytes received
   probe   — try channels 1-10, log which one responds
   send    — send raw hex bytes over open connection
   sniff   — passive capture: log every byte to file for Wireshark

 Build:
   swiftc glasses-tool.swift -framework IOBluetooth -framework Foundation \
          -o glasses-tool && chmod +x glasses-tool

 Usage:
   ./glasses-tool scan
   ./glasses-tool connect XX:XX:XX:XX:XX:XX
   ./glasses-tool probe  XX:XX:XX:XX:XX:XX
*/

import Foundation
import IOBluetooth

// ── ANSI colours ─────────────────────────────────────────────────────────────
let CLR_RED    = "\u{001B}[31m"
let CLR_GRN    = "\u{001B}[32m"
let CLR_YLW    = "\u{001B}[33m"
let CLR_BLU    = "\u{001B}[34m"
let CLR_MAG    = "\u{001B}[35m"
let CLR_CYN    = "\u{001B}[36m"
let CLR_RST    = "\u{001B}[0m"

func log(_ msg: String, color: String = CLR_RST) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("\(color)[\(ts)] \(msg)\(CLR_RST)")
    fflush(stdout)
}

// ── Hex helpers ───────────────────────────────────────────────────────────────
extension Data {
    var hexDump: String {
        let hex = map { String(format: "%02x", $0) }
        let asc = map { ($0 >= 0x20 && $0 < 0x7f) ? String(UnicodeScalar($0)) : "." }
        var out = ""
        for row in stride(from: 0, to: count, by: 16) {
            let end = Swift.min(row + 16, count)
            let h = hex[row..<end].joined(separator: " ").padding(toLength: 47, withPad: " ", startingAt: 0)
            let a = asc[row..<end].joined()
            out += String(format: "  %04x  %@ │%@│\n", row, h, a)
        }
        return out
    }
}

func hexToData(_ hex: String) -> Data? {
    let clean = hex.replacingOccurrences(of: " ", with: "")
                   .replacingOccurrences(of: "0x", with: "")
    guard clean.count % 2 == 0 else { return nil }
    var data = Data()
    var idx = clean.startIndex
    while idx < clean.endIndex {
        let next = clean.index(idx, offsetBy: 2)
        guard let byte = UInt8(clean[idx..<next], radix: 16) else { return nil }
        data.append(byte)
        idx = next
    }
    return data
}

// ── Capture log ───────────────────────────────────────────────────────────────
class CaptureLog {
    let path: String
    private var fh: FileHandle?
    private var byteCount = 0
    private let queue = DispatchQueue(label: "glasses.capture", qos: .utility)

    init(path: String) {
        self.path = path
        FileManager.default.createFile(atPath: path, contents: nil)
        fh = FileHandle(forWritingAtPath: path)
        log("📝 Capture log: \(path)", color: CLR_YLW)
    }

    func write(direction: String, data: Data) {
        // Capture values before dispatching to avoid closure-over-mutable issues
        let count = data.count
        let hex = data.hexDump
        let ts = Date().timeIntervalSince1970
        let tsInt = Int(ts)
        let tsFrac = Int((ts - Double(tsInt)) * 1000)
        let header = "[\(tsInt).\(String(format: "%03d", tsFrac))] \(direction) \(count) bytes\n"

        // Print to terminal immediately (main thread is fine for stdout)
        let dirColor = direction == " RX" ? CLR_GRN : CLR_BLU
        print("\(dirColor)\(header)\(hex)\(CLR_RST)", terminator: "")
        fflush(stdout)

        queue.async { [weak self] in
            guard let self = self else { return }
            self.byteCount += count
            let line = header + hex + "\n"
            self.fh?.write(Data(line.utf8))
        }
    }

    func close() {
        queue.sync {
            fh?.closeFile()
        }
        log("Capture saved: \(byteCount) bytes total → \(path)", color: CLR_YLW)
    }
}

// ── RFCOMM delegate ───────────────────────────────────────────────────────────
class RFCOMMDelegate: NSObject, IOBluetoothRFCOMMChannelDelegate {

    var onData: ((Data) -> Void)?
    var onOpen: ((IOBluetoothRFCOMMChannel) -> Void)?
    var onClose: (() -> Void)?

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                   status error: IOReturn) {
        if error == kIOReturnSuccess {
            log("✅ RFCOMM channel open (MTU: \(rfcommChannel.getMTU()))", color: CLR_GRN)
            gChannel = rfcommChannel // Retain globally to prevent deallocation
            onOpen?(rfcommChannel)
        } else {
            log("❌ RFCOMM open failed: 0x\(String(format: "%08x", error))", color: CLR_RED)
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        log("🔴 RFCOMM closed", color: CLR_RED)
        onClose?()
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                           data dataPointer: UnsafeMutableRawPointer!,
                           length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        onData?(data)
    }

    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                    refcon: UnsafeMutableRawPointer!,
                                    status error: IOReturn) {
        if error != kIOReturnSuccess {
            log("Write error: 0x\(String(format: "%08x", error))", color: CLR_RED)
        }
    }
}

// ── Commands ──────────────────────────────────────────────────────────────────

// MARK: scan
func cmdScan(duration: TimeInterval = 10.0) {
    log("🔍 Scanning for Bluetooth devices (\(Int(duration))s)...", color: CLR_CYN)
    log("   Power on the glasses, hold POWER switch 4+ seconds until text appears on lenses.", color: CLR_YLW)
    log("   Then wait for this scan to pick them up.", color: CLR_YLW)

    var seen = Set<String>()

    // List already-known devices first
    if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
        log("Paired devices:", color: CLR_MAG)
        for d in devices {
            let name = d.name ?? "(unknown)"
            let addr = d.addressString ?? ""
            log("  📱 \(name)  [\(addr)]", color: CLR_MAG)
            seen.insert(addr)
        }
    }

    // Inquiry scan
    guard let inquiry = IOBluetoothDeviceInquiry(delegate: nil) else {
        log("Failed to create inquiry", color: CLR_RED); return
    }
    inquiry.inquiryLength = UInt8(Swift.min(duration, 30))
    inquiry.start()

    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        if let found = inquiry.foundDevices() as? [IOBluetoothDevice] {
            for d in found {
                let addr = d.addressString ?? ""
                guard !seen.contains(addr) else { continue }
                seen.insert(addr)
                let name = d.name ?? "(discovering...)"
                let cls  = d.deviceClassMajor
                let icon = cls == kBluetoothDeviceClassMajorAudio ? "🎧" :
                           cls == kBluetoothDeviceClassMajorPhone  ? "📱" :
                           cls == kBluetoothDeviceClassMajorComputer ? "💻" : "📡"
                log("\(icon) Found: \(name)  [\(addr)]", color: CLR_GRN)
            }
        }
    }
    inquiry.stop()
    log("Scan complete. \(seen.count) devices total.", color: CLR_CYN)
    log("If SmartEyeglass appeared: run './glasses-tool connect XX:XX:XX:XX:XX:XX'", color: CLR_YLW)
}

// MARK: sdp — query SDP records for a device
func cmdSDP(address: String) {
    guard let device = IOBluetoothDevice(addressString: address) else {
        log("Device not found: \(address)", color: CLR_RED); return
    }
    log("Querying SDP records for \(device.name ?? address)...", color: CLR_CYN)
    device.performSDPQuery(nil)

    // Give it a moment
    RunLoop.current.run(until: Date().addingTimeInterval(5))

    guard let services = device.services as? [IOBluetoothSDPServiceRecord] else {
        log("No SDP records found", color: CLR_RED); return
    }

    log("SDP services (\(services.count)):", color: CLR_GRN)
    for (i, svc) in services.enumerated() {
        var channelID: BluetoothRFCOMMChannelID = 0
        let hasRFCOMM = svc.getRFCOMMChannelID(&channelID) == kIOReturnSuccess

        let nameAttr = svc.getAttributeDataElement(BluetoothSDPServiceAttributeID(kBluetoothSDPAttributeIdentifierServiceName.rawValue))
        let name = nameAttr?.getStringValue() ?? "(unnamed)"

        if hasRFCOMM {
            log("  [\(i)] \(CLR_BLU)\(name)\(CLR_GRN) — RFCOMM channel \(channelID) ← SPP candidate", color: CLR_GRN)
        } else {
            log("  [\(i)] \(name)", color: CLR_RST)
        }
    }
}

// ── Global references to prevent deallocation segfaults ────────────────────
var gChannel: IOBluetoothRFCOMMChannel?
var gDelegate: RFCOMMDelegate?
var gCapture: CaptureLog?
let gWriteQueue = DispatchQueue(label: "glasses.rfcomm.write", qos: .userInitiated)

// MARK: connect — open RFCOMM on given channel and dump bytes
// Test mode: "test" sends diagnostic patterns; "gol" runs Game of Life
enum DisplayMode { case test, gol }
var gDisplayMode: DisplayMode = .gol

func cmdConnect(address: String, channel: BluetoothRFCOMMChannelID = 0,
                captureFile: String? = nil) {
    guard let device = IOBluetoothDevice(addressString: address) else {
        log("Cannot create device for \(address) — is it paired?", color: CLR_RED)
        log("If not paired, open System Settings → Bluetooth → put glasses in pairing mode", color: CLR_YLW)
        return
    }

    let name = device.name ?? address
    log("Connecting to \(name) [\(address)]...", color: CLR_CYN)

    // Run SDP to find SPP channel
    device.performSDPQuery(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(4))

    // Determine channel
    var rfcommChannel: BluetoothRFCOMMChannelID = channel
    if rfcommChannel == 0 {
        if let services = device.services as? [IOBluetoothSDPServiceRecord] {
            for svc in services {
                var ch: BluetoothRFCOMMChannelID = 0
                if svc.getRFCOMMChannelID(&ch) == kIOReturnSuccess {
                    log("SPP found on channel \(ch) via SDP", color: CLR_GRN)
                    rfcommChannel = ch
                    break
                }
            }
        }
        if rfcommChannel == 0 {
            rfcommChannel = 1
            log("No SPP in SDP — defaulting to channel 1", color: CLR_YLW)
        }
    }

    gCapture = captureFile.map { CaptureLog(path: $0) }
    gDelegate = RFCOMMDelegate()

    var rxCount = 0
    // Phase machine:
    // 0 = wait ProtocolVersion
    // 1 = wait SettingsStatusResponse
    // 2 = wait VersionResponse
    // 3 = sent NewHostApp, wait for FotaStatus/ack
    // 4 = sent OpenAppStartReq, wait for OpenAppStartResponse (0x31)
    // 5 = display ready, sending frames
    var initPhase = 0

    // Helper to send a command frame — serialized via gWriteQueue
    func sendCmd(_ bytes: [UInt8], label: String) {
        guard let ch = gChannel else { log("TX failed: no channel", color: CLR_RED); return }
        let mtu = Int(ch.getMTU())
        let chunkSize = mtu > 0 ? mtu : 665  // fallback
        // Serialize all RFCOMM writes to prevent concurrent writeSync crashes
        gWriteQueue.sync {
            var offset = 0
            var ok = true
            while offset < bytes.count {
                let end = min(offset + chunkSize, bytes.count)
                var chunk = Array(bytes[offset..<end])
                let r = ch.writeSync(&chunk, length: UInt16(chunk.count))
                if r != 0 {
                    log("TX chunk error at offset \(offset): 0x\(String(format:"%x",r))", color: CLR_RED)
                    ok = false; break
                }
                offset = end
            }
            let preview = bytes.prefix(12).map{String(format:"%02x",$0)}.joined(separator:" ")
            log("→ TX \(label) \(bytes.count)B \(ok ? "OK" : "FAIL"): \(preview)...", color: CLR_BLU)
        }
        gCapture?.write(direction: " TX", data: Data(bytes))
    }

    // ── Game of Life engine ──────────────────────────────────────────────────
    let W = 419
    let H = 138
    var grid: [[Bool]] = []
    var golGeneration = 0
    var golPattern = 0
    let golPatternCount = 5
    var golTimer: Timer?

    func golInit() {
        grid = Array(repeating: Array(repeating: false, count: W), count: H)
        golGeneration = 0
    }

    func golLoadPattern(_ idx: Int) {
        golInit()
        switch idx {
        case 0: golLoadGliderGun()
        case 1: golLoadRandom(density: 0.35)
        case 2: golLoadPulsar()
        case 3: golLoadRandom(density: 0.5)
        case 4: golLoadSpaceships()
        default: golLoadRandom(density: 0.4)
        }
        log("🎮 Game of Life: pattern \(idx) loaded", color: CLR_MAG)
    }

    func golLoadRandom(density: Double) {
        for y in 0..<H {
            for x in 0..<W {
                grid[y][x] = Double.random(in: 0...1) < density
            }
        }
    }

    func golSet(_ cells: [(Int,Int)], ox: Int, oy: Int) {
        for (dx, dy) in cells {
            let x = ox + dx, y = oy + dy
            if x >= 0 && x < W && y >= 0 && y < H { grid[y][x] = true }
        }
    }

    func golLoadGliderGun() {
        // Gosper glider gun — place 3 copies across the display
        let gun: [(Int,Int)] = [
            (1,5),(1,6),(2,5),(2,6),
            (11,5),(11,6),(11,7),(12,4),(12,8),(13,3),(13,9),(14,3),(14,9),
            (15,6),(16,4),(16,8),(17,5),(17,6),(17,7),(18,6),
            (21,3),(21,4),(21,5),(22,3),(22,4),(22,5),(23,2),(23,6),
            (25,1),(25,2),(25,6),(25,7),
            (35,3),(35,4),(36,3),(36,4)
        ]
        golSet(gun, ox: 5, oy: 10)
        golSet(gun, ox: 5, oy: 60)
        golSet(gun, ox: 200, oy: 35)
    }

    func golLoadPulsar() {
        // Multiple pulsars (period 3)
        let pulsar: [(Int,Int)] = [
            (2,0),(3,0),(4,0),(8,0),(9,0),(10,0),
            (0,2),(5,2),(7,2),(12,2),
            (0,3),(5,3),(7,3),(12,3),
            (0,4),(5,4),(7,4),(12,4),
            (2,5),(3,5),(4,5),(8,5),(9,5),(10,5),
            (2,7),(3,7),(4,7),(8,7),(9,7),(10,7),
            (0,8),(5,8),(7,8),(12,8),
            (0,9),(5,9),(7,9),(12,9),
            (0,10),(5,10),(7,10),(12,10),
            (2,12),(3,12),(4,12),(8,12),(9,12),(10,12)
        ]
        golSet(pulsar, ox: 50, oy: 20)
        golSet(pulsar, ox: 200, oy: 20)
        golSet(pulsar, ox: 350, oy: 20)
        golSet(pulsar, ox: 125, oy: 60)
        golSet(pulsar, ox: 275, oy: 60)
    }

    func golLoadSpaceships() {
        // LWSS (lightweight spaceship) fleet
        let lwss: [(Int,Int)] = [
            (1,0),(4,0),(0,1),(0,2),(4,2),(0,3),(1,3),(2,3),(3,3)
        ]
        for row in 0..<6 {
            for col in 0..<8 {
                golSet(lwss, ox: 10 + col * 50, oy: 5 + row * 22)
            }
        }
        // Add some random spice
        for _ in 0..<500 {
            let x = Int.random(in: 0..<W)
            let y = Int.random(in: 0..<H)
            grid[y][x] = true
        }
    }

    func golStep() {
        var next = Array(repeating: Array(repeating: false, count: W), count: H)
        for y in 0..<H {
            for x in 0..<W {
                var n = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let nx = (x + dx + W) % W  // toroidal wrap
                        let ny = (y + dy + H) % H
                        if grid[ny][nx] { n += 1 }
                    }
                }
                if grid[y][x] {
                    next[y][x] = (n == 2 || n == 3)
                } else {
                    next[y][x] = (n == 3)
                }
            }
        }
        grid = next
        golGeneration += 1
    }

    func golToImage() -> [UInt8] {
        var img = [UInt8](repeating: 0, count: W * H)
        for y in 0..<H {
            for x in 0..<W {
                if grid[y][x] { img[y * W + x] = 255 }
            }
        }
        return img
    }

    // ── Build LayoutPlaceRemoveCommand (0xe7) with proper subcommands ────
    // 3 subcommands: PLACE_STATE(0x01) + PLACE_IMGOBJ(0x03) + PLACE_IMAGEDATA(0x07)
    // Image data is 8-bit grayscale, DEFLATE compressed, imgFormat=0x01
    func buildLayoutDisplayCmd(grayscale: [UInt8]) -> [UInt8] {
        // DEFLATE compress the grayscale data (raw, no zlib header)
        let compressed = deflateCompress(grayscale)
        log("   Compressed: \(grayscale.count)B → \(compressed.count)B (\(Int(Double(compressed.count)/Double(grayscale.count)*100))%)", color: CLR_CYN)

        // Subcommand 1: PLACE_STATE (type=0x01, 10 bytes data)
        var sub1: [UInt8] = [0x01, 0x00, 0x0a]  // type, len=10
        sub1 += [0x00, 0x00]  // stateId = 0 (must match LayoutInit state)
        sub1 += [0x00, 0x00]  // initJogPos = 0
        sub1 += [0x00, 0x00]  // minJogPos = 0
        sub1 += [0x00, 0x00]  // maxJogPos = 0
        sub1 += [0x00, 0x00]  // options = 0

        // Subcommand 2: PLACE_IMGOBJ (type=0x03, 24 bytes data)
        var sub2: [UInt8] = [0x03, 0x00, 0x18]  // type, len=24
        sub2 += [0x00, 0x00]  // objId = 0
        sub2 += [0x00]        // layerId = 0
        sub2 += [0x00]        // padding
        sub2 += [0x00, 0x00, 0x00, 0x00]  // x = 0
        sub2 += [0x00, 0x00, 0x00, 0x00]  // y = 0
        sub2 += [0x01, 0xa3]  // width = 419
        sub2 += [0x00, 0x8a]  // height = 138
        sub2 += [0x00]        // isSticky = false
        sub2 += [0x00, 0x00, 0x00, 0x00]  // reserved
        sub2 += [0x00]        // subtype = IMAGE
        sub2 += [0x00, 0x00]  // loadingId = 0

        // Subcommand 3: PLACE_IMAGEDATA (type=0x07)
        let imgDataLen = 2 + 1 + compressed.count  // objId(2) + fmt(1) + data
        var sub3: [UInt8] = [0x07]
        sub3.append(UInt8((imgDataLen >> 8) & 0xff))
        sub3.append(UInt8(imgDataLen & 0xff))
        sub3 += [0x00, 0x00]  // objId = 0 (must match PLACE_IMGOBJ)
        sub3 += [0x01]        // imgFormat = 1 (8-bit mono, deflated)
        sub3 += compressed

        // Total payload = sub1 + sub2 + sub3
        let totalPayload = sub1.count + sub2.count + sub3.count
        var cmd: [UInt8] = [0xe7]
        cmd.append(UInt8((totalPayload >> 8) & 0xff))
        cmd.append(UInt8(totalPayload & 0xff))
        cmd += sub1
        cmd += sub2
        cmd += sub3
        return cmd
    }

    // DEFLATE compress using Python via stdin/stdout pipes (raw deflate, wbits=-15, level 9)
    // Java Deflater(nowrap=true) = Python zlib.compressobj(wbits=-15)
    func deflateCompress(_ input: [UInt8]) -> [UInt8] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["-c",
            "import zlib,sys; d=sys.stdin.buffer.read(); c=zlib.compressobj(9,zlib.DEFLATED,-15); sys.stdout.buffer.write(c.compress(d)+c.flush())"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            stdinPipe.fileHandleForWriting.write(Data(input))
            stdinPipe.fileHandleForWriting.closeFile()
            proc.waitUntilExit()
            let result = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            if !result.isEmpty { return Array(result) }
        } catch {
            log("⚠️ DEFLATE process error: \(error)", color: CLR_RED)
        }
        log("⚠️ DEFLATE failed, sending uncompressed", color: CLR_RED)
        return input
    }

    // ── Interactive REPL ────────────────────────────────────────────────
    func printREPLHelp() {
        print("""
        \(CLR_CYN)
        ═══ INTERACTIVE MODE ═══
        Type commands below. The glasses are connected and handshake done.\(CLR_RST)

        \(CLR_GRN)Display setup:\(CLR_RST)
          start     — send OpenAppStartRequest (0x30)
          on        — DisplayTurnOnOff ON (0xe9 01)
          off       — DisplayTurnOnOff OFF (0xe9 00)
          mode N    — OpenAppMode (0=normal, 1=AR) (0xc3)
          clear     — OpenAppClearScreen (0xb1)
          screen N  — SetScreenState (0x3d, N=0/1)
          linit     — LayoutInit 419×138 (0xe0)

        \(CLR_GRN)Image commands (Layout 0xe7, 8-bit grayscale+DEFLATE):\(CLR_RST)
          white     — all pixels ON
          black     — all pixels OFF
          checker   — 16px checkerboard
          stripes   — horizontal stripes
          cross     — crosshair pattern

        \(CLR_GRN)Other:\(CLR_RST)
          gol       — start Game of Life animation
          raw HEX   — send raw hex bytes (e.g. 'raw e9 00 01 01')
          help      — show this help
          quit      — disconnect and exit

        \(CLR_YLW)↑↑↑ LOOK AT THE GLASSES AFTER EACH COMMAND ↑↑↑
        Tell me what you see: nothing, flicker, pattern, all green, etc.\(CLR_RST)
        """)
        print("\(CLR_MAG)> \(CLR_RST)", terminator: "")
        fflush(stdout)
    }

    func handleREPLCommand(_ line: String) {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased().split(separator: " ")
        guard let cmd = parts.first else {
            print("\(CLR_MAG)> \(CLR_RST)", terminator: ""); fflush(stdout)
            return
        }

        switch cmd {
        case "start":
            sendCmd([0x30, 0x00, 0x00], label: "OpenAppStartRequest")

        case "on":
            sendCmd([0xe9, 0x00, 0x01, 0x01], label: "DisplayTurnOn")

        case "off":
            sendCmd([0xe9, 0x00, 0x01, 0x00], label: "DisplayTurnOff")

        case "mode":
            let m = parts.count > 1 ? (UInt8(parts[1]) ?? 0) : 0
            sendCmd([0xc3, 0x00, 0x01, m], label: "OpenAppMode(\(m))")

        case "clear":
            sendCmd([0xb1, 0x00, 0x00], label: "OpenAppClearScreen")

        case "screen":
            let s = parts.count > 1 ? (UInt8(parts[1]) ?? 1) : 1
            sendCmd([0x3d, 0x00, 0x01, s], label: "SetScreenState(\(s))")

        case "linit":
            sendCmd([0xe0, 0x00, 0x0a,
                     0x00, 0x00, 0x00, 0x00,  // viewX=0
                     0x00, 0x00, 0x00, 0x00,  // viewY=0
                     0x00, 0x00],              // state=0
                    label: "LayoutInit(0,0,state=0)")

        case "white":
            let gray = [UInt8](repeating: 0xFF, count: W * H)
            sendCmd(buildLayoutDisplayCmd(grayscale: gray), label: "LAYOUT all-white")

        case "black":
            let gray = [UInt8](repeating: 0x00, count: W * H)
            sendCmd(buildLayoutDisplayCmd(grayscale: gray), label: "LAYOUT all-black")

        case "checker":
            var gray = [UInt8](repeating: 0, count: W * H)
            for y in 0..<H { for x in 0..<W {
                if (x / 16 + y / 16) % 2 == 0 { gray[y * W + x] = 255 }
            }}
            sendCmd(buildLayoutDisplayCmd(grayscale: gray), label: "LAYOUT checker")

        case "stripes":
            var gray = [UInt8](repeating: 0, count: W * H)
            for y in 0..<H { if y % 8 < 4 {
                for x in 0..<W { gray[y * W + x] = 255 }
            }}
            sendCmd(buildLayoutDisplayCmd(grayscale: gray), label: "LAYOUT stripes")

        case "cross":
            var gray = [UInt8](repeating: 0, count: W * H)
            let cx = W / 2, cy = H / 2
            for x in 0..<W { gray[cy * W + x] = 255 }
            for y in 0..<H { gray[y * W + cx] = 255 }
            for x in 0..<W { gray[x] = 255; gray[(H-1) * W + x] = 255 }
            for y in 0..<H { gray[y * W] = 255; gray[y * W + W - 1] = 255 }
            sendCmd(buildLayoutDisplayCmd(grayscale: gray), label: "LAYOUT cross")

        case "gol":
            log("🎮 Starting Game of Life!", color: CLR_MAG)
            golStartLoop()

        case "raw":
            let hexStr = parts.dropFirst().joined(separator: "")
            if let data = hexToData(hexStr) {
                sendCmd(Array(data), label: "RAW \(data.count)B")
            } else {
                log("Invalid hex. Usage: raw e9 00 01 01", color: CLR_RED)
            }

        case "help", "h", "?":
            printREPLHelp()
            return  // skip prompt

        case "quit", "exit", "q":
            log("👋 Disconnecting...", color: CLR_YLW)
            gChannel?.close()
            exit(0)

        default:
            log("Unknown command: \(cmd). Type 'help' for commands.", color: CLR_RED)
        }

        print("\(CLR_MAG)> \(CLR_RST)", terminator: "")
        fflush(stdout)
    }

    func golSendFrame() {
        let gray = golToImage()  // already 8-bit: 0 or 255
        let cmd = buildLayoutDisplayCmd(grayscale: gray)
        sendCmd(cmd, label: "GOL gen=\(golGeneration)")
    }

    func golStartLoop() {
        golPattern = 3  // Start with dense random (50%)
        golLoadPattern(golPattern)
        golSendFrame()

        // 1fps — BT can handle ~57KB/s, each frame is 57KB
        golTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            golStep()
            golStep()  // 2 steps per frame for faster evolution
            golStep()
            golSendFrame()
            if golGeneration % 60 == 0 {
                golPattern = (golPattern + 1) % golPatternCount
                golLoadPattern(golPattern)
                log("🎮 Switched to pattern \(golPattern)", color: CLR_MAG)
            }
        }
        RunLoop.current.add(golTimer!, forMode: .default)
    }

    // ── Wire up delegates AFTER all vars/funcs declared ──────────────────
    gDelegate?.onOpen = { channel in
        log("RFCOMM open on ch\(rfcommChannel), MTU=\(channel.getMTU())", color: CLR_GRN)
        log("Handshake: ProtocolVersion → SettingsStatus → Version → NewHostApp → SyncResponse", color: CLR_YLW)
        // Start stdin reader unconditionally so 'quit' etc. always work
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine() {
                DispatchQueue.main.async { handleREPLCommand(line) }
            }
        }
    }

    gDelegate?.onData = { data in
        rxCount += data.count
        log("← RX \(data.count) bytes (total \(rxCount)):", color: CLR_GRN)
        print(data.hexDump)
        gCapture?.write(direction: " RX", data: data)

        guard data.count >= 3 else { return }
        let cmdId = data[0]

        switch (initPhase, cmdId) {

        case (0, 0x0a): // ProtocolVersion from glasses
            initPhase = 1
            log("✨ Phase 1: Got ProtocolVersion. Sending SettingsStatusRequest...", color: CLR_MAG)
            // Reply with SettingsStatusRequest (cmd=0x71, len=0)
            sendCmd([0x71, 0x00, 0x00], label: "SettingsStatusRequest")

        case (1, 0x72): // SettingsStatusResponse
            initPhase = 2
            log("✨ Phase 2: Got SettingsStatusResponse. Sending VersionRequest...", color: CLR_MAG)
            // Send VersionRequest (cmd=0x07, len=1, payload=0x01)
            sendCmd([0x07, 0x00, 0x01, 0x01], label: "VersionRequest")

        case (2, 0x08): // VersionResponse
            initPhase = 3
            if data.count > 3 {
                let versionBytes = Array(data[3...])
                let version = String(bytes: versionBytes, encoding: .ascii) ?? "?"
                log("✨ Phase 3: FW version=\(version). Sending NewHostApp...", color: CLR_MAG)
            }
            // Send NewHostApp (cmd=0x85, len=4, status=0)
            sendCmd([0x85, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00], label: "NewHostApp(0)")

            // Wait up to 5s for FotaStatus before advancing
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                guard initPhase == 3 else { return }
                log("⏳ No FotaStatus after 5s — sending OpenAppStart...", color: CLR_YLW)
                initPhase = 4
                sendCmd([0x30, 0x00, 0x00], label: "OpenAppStartRequest")
                log("👉 TAP the glasses controller touch sensor to confirm!", color: CLR_YLW)
            }

        case (3, 0x81): // FotaStatus — firmware update info
            log("✨ Phase 3: Got FotaStatus. Sending SyncResponse to unblock glasses...", color: CLR_MAG)
            // SyncResponse (0xFF) is CRITICAL — unlocks the glasses' command processing
            sendCmd([0xff, 0x00, 0x00], label: "SyncResponse")
            initPhase = 4  // Wait for LevelNotification / user interaction
            log("", color: CLR_RST)
            log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", color: CLR_YLW)
            log("👓 WAITING. Complete the glasses visual test first.", color: CLR_YLW)
            log("👓 Then tap the touch sensor. Type 'help' for commands.", color: CLR_YLW)
            log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", color: CLR_YLW)

        case (3, _): // Phase 3: other responses while waiting for FotaStatus
            log("✨ Phase 3: got cmd=0x\(String(format:"%02x",cmdId)) — ignoring, waiting for FotaStatus", color: CLR_YLW)

        case (4, 0x31): // OpenAppStartResponse — glasses accepted our app!
            log("🎉 Phase 4→5: OpenAppStartResponse! Glasses confirmed!", color: CLR_GRN)
            initPhase = 5
            // Proceed to display setup via LayoutInit + image
            sendCmd([0xe0, 0x00, 0x0a,
                     0x00, 0x00, 0x00, 0x00,
                     0x00, 0x00, 0x00, 0x00,
                     0x00, 0x00],
                    label: "LayoutInit(0,0,state=0)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let gray = [UInt8](repeating: 0xFF, count: W * H)
                sendCmd(buildLayoutDisplayCmd(grayscale: gray), label: "LAYOUT all-white")
                log("✨ Layout image sent!", color: CLR_GRN)
                if gDisplayMode == .test {
                    printREPLHelp()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        log("🎮 Starting Game of Life!", color: CLR_MAG)
                        golStartLoop()
                    }
                }
            }

        case (4, 0x06): // LevelNotification — glasses confirmed connection!
            let level = data.count > 3 ? data[3] : 0
            log("🎉 Phase 4→5: LevelNotification (level=\(level))! Glasses READY! Sending image!", color: CLR_GRN)
            initPhase = 5

            // Send OpenAppStart + LayoutInit + image
            sendCmd([0x30, 0x00, 0x00], label: "OpenAppStartRequest")
            sendCmd([0xe0, 0x00, 0x0a,
                     0x00, 0x00, 0x00, 0x00,  // viewX=0
                     0x00, 0x00, 0x00, 0x00,  // viewY=0
                     0x00, 0x00],              // state=0
                    label: "LayoutInit(0,0,state=0)")

            // Send image via Layout path (8-bit mono + DEFLATE)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let gray = [UInt8](repeating: 0xFF, count: W * H)
                sendCmd(buildLayoutDisplayCmd(grayscale: gray), label: "LAYOUT all-white")
                log("✨ Layout image sent! LOOK AT THE GLASSES!", color: CLR_GRN)

                if gDisplayMode == .test {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { printREPLHelp() }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        log("🎮 Starting Game of Life!", color: CLR_MAG)
                        golStartLoop()
                    }
                }
            }

        case (4, 0x81): // Another FotaStatus while waiting
            log("✨ Phase 4: FotaStatus (ignoring, waiting for LevelNotification or StartResponse)", color: CLR_YLW)

        case (4, 0xe5): // LayoutEventNotify — touch/navigation events from glasses UI
            // Suppress flood logging
            break

        case (4, _): // Phase 4: other responses
            log("✨ Phase 4: got cmd=0x\(String(format:"%02x",cmdId))", color: CLR_YLW)

        case (5, _): // Fully initialized — log everything
            let cmdName: String
            switch cmdId {
            case 0x01: cmdName = "ACK"
            case 0x02: cmdName = "NAK"
            case 0x05: cmdName = "PING"
            case 0x06: cmdName = "LEVEL_NOTIFICATION"
            case 0x32: cmdName = "TOUCH"
            case 0x36: cmdName = "IMAGE_ACK"
            case 0x3c: cmdName = "KEY_EVENT"
            default: cmdName = String(format: "CMD_0x%02x", cmdId)
            }
            log("   [\(cmdName)]", color: CLR_CYN)

        case (_, 0x0a) where initPhase > 0: // Re-received ProtocolVersion at any phase
            initPhase = 1
            log("✨ Re-received ProtocolVersion. Restarting handshake...", color: CLR_MAG)
            sendCmd([0x71, 0x00, 0x00], label: "SettingsStatusRequest")

        default:
            log("   [phase=\(initPhase) cmd=0x\(String(format:"%02x",cmdId))]", color: CLR_YLW)
        }
    }

    gDelegate?.onClose = {
        log("Disconnected after \(rxCount) bytes received", color: CLR_RED)
        gCapture?.close()
        exit(0)
    }

    var tempChannel: IOBluetoothRFCOMMChannel?
    let result = device.openRFCOMMChannelAsync(&tempChannel,
                                               withChannelID: rfcommChannel,
                                               delegate: gDelegate)
    guard result == kIOReturnSuccess else {
        log("openRFCOMMChannelAsync failed: 0x\(String(format: "%08x", result))", color: CLR_RED)
        log("Possible causes:", color: CLR_YLW)
        log("  • Glasses not paired with this Mac", color: CLR_YLW)
        log("  • Glasses not in the Bluetooth pairing list", color: CLR_YLW)
        log("  • Wrong channel number (try ./glasses-tool probe \(address))", color: CLR_YLW)
        return
    }

    log("RFCOMM connection in progress...", color: CLR_CYN)

    // Run until disconnected
    RunLoop.current.run()
    gCapture?.close()
}

// MARK: probe — try channels 1..10 and see which opens
func cmdProbe(address: String) {
    log("Probing RFCOMM channels 1-10 on \(address)...", color: CLR_CYN)
    log("Looking for channel that stays open (SPP = Serial Port Profile)", color: CLR_YLW)

    guard let device = IOBluetoothDevice(addressString: address) else {
        log("Device not found: \(address)", color: CLR_RED); return
    }

    device.performSDPQuery(nil)
    RunLoop.current.run(until: Date().addingTimeInterval(4))

    for ch in UInt8(1)...UInt8(10) {
        var channelObj: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelSync(&channelObj, withChannelID: ch, delegate: nil)
        if result == kIOReturnSuccess, let ch_obj = channelObj {
            let mtu = ch_obj.getMTU()
            log("  ✅ Channel \(ch): OPEN (MTU=\(mtu)) ← likely SPP", color: CLR_GRN)
            ch_obj.close()
        } else {
            log("  ✗  Channel \(ch): closed/refused (0x\(String(format: "%x", result)))", color: CLR_RST)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }
    log("Probe complete. Use './glasses-tool connect \(address) --channel N' with working channel.", color: CLR_CYN)
}

// MARK: pair — guide user through pairing
func cmdPairGuide(address: String? = nil) {
    print("""
    \(CLR_CYN)
    ╔══════════════════════════════════════════════════════════════════╗
    ║   Sony SED-E1 macOS Pairing Guide                              ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║                                                                  ║
    ║  STEP 1: Power on the glasses                                   ║
    ║  ────────────────────────────────────────────────────────────── ║
    ║  Slide the POWER switch toward ON/OFF and HOLD 4+ seconds.     ║
    ║  Text appears on the lenses (only visible when wearing them).   ║
    ║                                                                  ║
    ║  STEP 2: Put glasses in BT pairing mode                        ║
    ║  ────────────────────────────────────────────────────────────── ║
    ║  The glasses should advertise as "SmartEyeglass".              ║
    ║  If they don't appear: power cycle and try again.              ║
    ║                                                                  ║
    ║  STEP 3: Pair from System Settings                             ║
    ║  ────────────────────────────────────────────────────────────── ║
    ║  System Settings → Bluetooth → wait for SmartEyeglass          ║
    ║  Click "Connect" → enter passkey if prompted                   ║
    ║  Tap the touch sensor on the controller to confirm             ║
    ║                                                                  ║
    ║  STEP 4: Find the BT address                                   ║
    ║  ────────────────────────────────────────────────────────────── ║
    ║  Once paired, run: ./glasses-tool scan                         ║
    ║  Or check System Settings → Bluetooth → SmartEyeglass → (i)  ║
    ║                                                                  ║
    ║  STEP 5: Connect and sniff                                     ║
    ║  ────────────────────────────────────────────────────────────── ║
    ║  ./glasses-tool sdp  XX:XX:XX:XX:XX:XX    (find channels)     ║
    ║  ./glasses-tool probe XX:XX:XX:XX:XX:XX   (test channels)     ║
    ║  ./glasses-tool connect XX:XX:XX:XX:XX:XX (connect + dump)    ║
    ║                                                                  ║
    ╚══════════════════════════════════════════════════════════════════╝
    \(CLR_RST)
    """)

    if let address = address {
        log("Attempting to connect to \(address)...", color: CLR_YLW)
        cmdConnect(address: address, captureFile: "/tmp/glasses_capture.log")
    }
}

// ── Config file ───────────────────────────────────────────────────────────────

struct GlassesConfig {
    var btAddress: String = "ac:9b:0a:37:a6:c6"
    var rfcommChannel: BluetoothRFCOMMChannelID = 4
    var captureLog: String = "/tmp/glasses_capture.log"

    /// Load from glasses.conf next to the binary, or fallback to defaults.
    static func load() -> GlassesConfig {
        var cfg = GlassesConfig()
        // Look for glasses.conf next to the executable, then in cwd
        let candidates = [
            URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .appendingPathComponent("glasses.conf").path,
            "glasses.conf",
            FileManager.default.currentDirectoryPath + "/glasses.conf"
        ]
        for path in candidates {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            log("📋 Config: \(path)", color: CLR_CYN)
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let val = parts[1].trimmingCharacters(in: .whitespaces)
                switch key {
                case "bt_address":     cfg.btAddress = val
                case "rfcomm_channel": cfg.rfcommChannel = BluetoothRFCOMMChannelID(val) ?? 4
                case "capture_log":    cfg.captureLog = val
                default: break
                }
            }
            break  // use first found
        }
        return cfg
    }
}

let config = GlassesConfig.load()

// ── Entry point ───────────────────────────────────────────────────────────────

let args = CommandLine.arguments

func usage() {
    print("""
    \(CLR_CYN)glasses-tool — Sony SED-E1 macOS connection utility\(CLR_RST)

    Config: glasses.conf (bt_address=\(config.btAddress) rfcomm_channel=\(config.rfcommChannel))

    Usage:
      \(CLR_GRN)./glasses-tool\(CLR_RST)                  — connect using glasses.conf defaults (GoL)
      \(CLR_GRN)./glasses-tool test\(CLR_RST)              — display diagnostic: 6 patterns × 3s each
      \(CLR_GRN)./glasses-tool scan\(CLR_RST)              — discover nearby BT devices
      \(CLR_GRN)./glasses-tool pair\(CLR_RST)              — show pairing guide
      \(CLR_GRN)./glasses-tool sdp\(CLR_RST)               — query SDP service records
      \(CLR_GRN)./glasses-tool probe\(CLR_RST)             — probe RFCOMM channels 1-10
      \(CLR_GRN)./glasses-tool connect\(CLR_RST)           — connect + handshake + Game of Life
      \(CLR_GRN)./glasses-tool connect XX:XX:XX:XX:XX:XX\(CLR_RST)  — override address

    All raw bytes are printed as hex+ASCII dumps.
    Capture log: \(config.captureLog)
    """)
}

// No args → connect with defaults
if args.count < 2 {
    log("🔌 Connecting to \(config.btAddress) ch=\(config.rfcommChannel)...", color: CLR_CYN)
    cmdConnect(address: config.btAddress, channel: config.rfcommChannel,
              captureFile: config.captureLog)
} else {
    switch args[1] {
    case "scan":
        cmdScan()
    case "pair":
        cmdPairGuide(address: args.count > 2 ? args[2] : config.btAddress)
    case "sdp":
        cmdSDP(address: args.count > 2 ? args[2] : config.btAddress)
    case "probe":
        cmdProbe(address: args.count > 2 ? args[2] : config.btAddress)
    case "test":
        gDisplayMode = .test
        let addr = args.count > 2 ? args[2] : config.btAddress
        log("🧪 Display test mode — will send 6 diagnostic patterns", color: CLR_MAG)
        cmdConnect(address: addr, channel: config.rfcommChannel, captureFile: config.captureLog)
    case "connect":
        let addr = args.count > 2 ? args[2] : config.btAddress
        var ch = config.rfcommChannel
        if let idx = args.firstIndex(of: "--channel"), args.count > idx + 1 {
            ch = BluetoothRFCOMMChannelID(args[idx + 1]) ?? ch
        }
        cmdConnect(address: addr, channel: ch, captureFile: config.captureLog)
    case "-h", "--help", "help":
        usage()
        exit(0)
    default:
        if args[1].contains(":") {
            // Bare address → connect
            cmdConnect(address: args[1], channel: config.rfcommChannel,
                      captureFile: config.captureLog)
        } else {
            usage()
        }
    }
}

RunLoop.main.run()
