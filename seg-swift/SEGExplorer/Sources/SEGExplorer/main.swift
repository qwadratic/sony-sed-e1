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
    } else {
        print("Usage: SEGExplorer --local HOST:PORT")
        print("Example: SEGExplorer --local 127.0.0.1:7002")
        exit(0)
    }
    await app.start()
}

// Keep running
RunLoop.current.run()
