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
        let allDevices = GlassesConnection.listPairedDevices()
        guard !allDevices.isEmpty else {
            print("No paired Bluetooth devices found.")
            print("Pair your glasses in System Settings → Bluetooth first.")
            exit(1)
        }

        let selectedAddress: String
        if let addr = btAddress {
            selectedAddress = addr
        } else {
            print("Paired Bluetooth devices:")
            print("")
            for (i, d) in allDevices.enumerated() {
                let icon: String
                if d.isGlasses {
                    icon = d.isOnline ? "🕶️" : "💤"
                } else {
                    icon = d.isOnline ? "🟢" : "⚪"
                }
                let signal = d.isOnline ? "rssi:\(d.rssi)dBm" : "offline"
                let tag = d.isGlasses ? " ← SmartEyeglass" : ""
                print("  [\(i)] \(icon) \(d.name)  [\(d.address)]  \(signal)\(tag)")
            }
            print("")
            
            // Auto-select if exactly one glasses device is online
            let onlineGlasses = allDevices.enumerated().filter { $0.element.isGlasses && $0.element.isOnline }
            if onlineGlasses.count == 1 {
                let (idx, d) = onlineGlasses[0]
                print("Auto-selecting only online glasses: [\(idx)] \(d.name)")
                selectedAddress = d.address
            } else {
                print("Select device [0-\(allDevices.count - 1)]: ", terminator: "")
                fflush(stdout)
                guard let line = readLine(),
                      let idx = Int(line.trimmingCharacters(in: .whitespaces)),
                      idx >= 0, idx < allDevices.count else {
                    print("Invalid selection.")
                    exit(1)
                }
                selectedAddress = allDevices[idx].address
                print("→ \(allDevices[idx].name) [\(selectedAddress)]")
            }
        }

        do {
            try await app.glasses.connectBluetooth(address: selectedAddress)
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
