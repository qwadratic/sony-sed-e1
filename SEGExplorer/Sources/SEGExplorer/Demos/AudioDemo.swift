import SEGKit
import Foundation

/// Audio: Mic — record from glasses microphone via BT HFP.
final class AudioDemo: Demo {
    let name = "Audio: Mic"
    private var glasses: GlassesConnection?
    private let fb = FrameBuffer()
    private var recording = false
    private var ffmpegProcess: Process?
    private var outputPath = ""
    private var startTime: Date?

    func onEnter(glasses: GlassesConnection) async {
        self.glasses = glasses
        recording = false
        fb.clear()
        TextRenderer.drawText("AUDIO CAPTURE", x: 4, y: 4, on: fb)
        TextRenderer.drawText("Uses BT HFP microphone", x: 4, y: 24, on: fb)
        TextRenderer.drawText("[tap] start recording", x: 4, y: fb.height - 10, on: fb)
        await glasses.display.show(fb.pixels)

        // List available audio input devices
        listAudioDevices()
    }

    func onTap() async {
        if !recording {
            recording = true
            startTime = Date()
            let ts = Int(Date().timeIntervalSince1970)
            outputPath = "/tmp/seg-audio-\(ts).wav"

            startRecording()

            fb.clear()
            TextRenderer.drawText("RECORDING...", x: 4, y: 4, on: fb, value: 255)
            TextRenderer.drawText("Output: \(outputPath)", x: 4, y: 24, on: fb)
            TextRenderer.drawText("[tap] stop", x: 4, y: fb.height - 10, on: fb)
            await glasses?.display.show(fb.pixels)
        } else {
            recording = false
            stopRecording()

            let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0

            print(String(format: "[AUDIO] Stopped. %.1fs, %d bytes → %@", duration, fileSize, outputPath))

            fb.clear()
            TextRenderer.drawText(String(format: "Recorded %.1fs", duration), x: 4, y: 20, on: fb)
            TextRenderer.drawText("\(fileSize) bytes", x: 4, y: 36, on: fb)
            TextRenderer.drawText(outputPath, x: 4, y: 52, on: fb)
            TextRenderer.drawText("[tap] record again", x: 4, y: fb.height - 10, on: fb)
            await glasses?.display.show(fb.pixels)
        }
    }

    func onSwipe(_ direction: InputEvent) async {}

    func onExit() async {
        if recording { stopRecording() }
        glasses = nil
    }

    // MARK: - Audio recording via ffmpeg

    private func listAudioDevices() {
        // List macOS audio input devices via ffmpeg
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        proc.arguments = ["-f", "avfoundation", "-list_devices", "true", "-i", ""]
        let pipe = Pipe()
        proc.standardError = pipe  // ffmpeg outputs device list to stderr
        proc.standardOutput = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Print audio input devices
        let lines = output.split(separator: "\n")
        print("[AUDIO] Available input devices:")
        for line in lines {
            if line.contains("AVFoundation audio devices") || line.contains("] [") {
                print("  \(line)")
            }
        }
    }

    private func startRecording() {
        // Record from default audio input using ffmpeg
        // -f avfoundation -i ":default" captures default mic
        // For BT mic specifically, user may need to set it as default input
        // in System Settings → Sound → Input
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        proc.arguments = [
            "-y",                    // overwrite
            "-f", "avfoundation",    // macOS audio capture
            "-i", ":default",        // default audio input device
            "-acodec", "pcm_s16le",  // WAV format
            "-ar", "16000",          // 16kHz sample rate (BT SCO typical)
            "-ac", "1",              // mono
            outputPath
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            ffmpegProcess = proc
            print("[AUDIO] Recording started → \(outputPath)")
            print("[AUDIO] NOTE: Set glasses as audio input in System Settings → Sound → Input")
        } catch {
            print("[AUDIO] Failed to start ffmpeg: \(error)")
        }
    }

    private func stopRecording() {
        // Send SIGINT to ffmpeg to stop recording gracefully
        if let proc = ffmpegProcess, proc.isRunning {
            proc.interrupt()  // sends SIGINT
            proc.waitUntilExit()
        }
        ffmpegProcess = nil
    }
}
