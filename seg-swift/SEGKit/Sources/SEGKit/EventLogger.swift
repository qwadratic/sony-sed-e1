import Foundation

/// Structured event logger. Writes JSONL to /tmp/seg-events.jsonl.
/// Internal to SEGKit — extension apps observe via GlassesDelegate.
public final class EventLogger: @unchecked Sendable {
    private let fileHandle: FileHandle?
    private let path: String

    public init(path: String = "/tmp/seg-events.jsonl") {
        self.path = path
        // Truncate on start
        FileManager.default.createFile(atPath: path, contents: nil)
        self.fileHandle = FileHandle(forWritingAtPath: path)
    }

    public func log(_ type: String, _ fields: [String: Any]) {
        var dict = fields
        dict["type"] = type
        dict["ts"] = Date().timeIntervalSince1970 * 1000
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           var line = String(data: data, encoding: .utf8) {
            line += "\n"
            fileHandle?.write(line.data(using: .utf8)!)
        }
    }

    deinit { fileHandle?.closeFile() }
}
