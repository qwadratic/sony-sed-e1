import Foundation
import SEGKit

let app = ExplorerApp()

// Parse --local HOST:PORT
var localHost: String? = nil
var localPort: UInt16 = 0

let args = CommandLine.arguments
if let idx = args.firstIndex(of: "--local"), idx + 1 < args.count {
    let parts = args[idx + 1].split(separator: ":")
    if parts.count == 2, let p = UInt16(parts[1]) {
        localHost = String(parts[0])
        localPort = p
    }
}

// Parse --bt and optional --address XX:XX:XX:XX:XX:XX
var btMode = args.contains("--bt")
var btAddress: String? = nil
if let idx = args.firstIndex(of: "--address"), idx + 1 < args.count {
    btAddress = args[idx + 1]
    btMode = true
}

Task {
    if let host = localHost {
        print("Connecting to \(host):\(localPort)...")
        do {
            try await app.glasses.connectLocal(host: host, port: localPort)
            print("Connected! Waiting for handshake...")
        } catch {
            print("Connection failed: \(error)")
            exit(1)
        }
    } else if btMode {
        print("Scanning for SmartEyeglass...")
        let smartDevices = GlassesConnection.listPairedDevices().filter {
            $0.name.lowercased().contains("smart") || $0.name.lowercased().contains("sed")
        }
        if !smartDevices.isEmpty {
            for (i, d) in smartDevices.enumerated() {
                print("  [\(i)] \(d.name) [\(d.address)]")
            }
        }
        do {
            try await app.glasses.connectBluetooth(address: btAddress)
            print("BT connected! Waiting for handshake...")
        } catch {
            print("BT connection failed: \(error)")
            exit(1)
        }
    } else {
        print("Usage:")
        print("  SEGExplorer --local HOST:PORT   (emulator/ADB)")
        print("  SEGExplorer --bt                (scan for SmartEyeglass)")
        print("  SEGExplorer --bt --address XX:XX:XX:XX:XX:XX")
        exit(0)
    }
    await app.start()
}

// Keep running
RunLoop.current.run()
