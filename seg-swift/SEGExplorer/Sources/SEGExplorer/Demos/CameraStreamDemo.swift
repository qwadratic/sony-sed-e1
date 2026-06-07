import Foundation
import SEGKit

/// Camera: Stream — continuous JPEG streaming with frame recording.
final class CameraStreamDemo: Demo {
    let name = "Camera: Stream"
    private var glasses: GlassesConnection?
    private let fb = FrameBuffer()
    private var streaming = false
    private var frameCount = 0
    private var startTime: ContinuousClock.Instant?
    private var sessionDir: String = ""

    func onEnter(glasses: GlassesConnection) async {
        self.glasses = glasses
        streaming = false
        frameCount = 0
        fb.clear()
        TextRenderer.drawText("CAMERA STREAM", x: 4, y: 4, on: fb)
        TextRenderer.drawText("[tap] start recording", x: 4, y: 60, on: fb)
        await glasses.display.show(fb.pixels)
    }

    func onTap() async {
        if !streaming {
            streaming = true
            frameCount = 0
            startTime = .now

            // Create timestamped output directory
            let ts = Int(Date().timeIntervalSince1970)
            sessionDir = "/tmp/seg-video-\(ts)"
            try? FileManager.default.createDirectory(
                atPath: sessionDir, withIntermediateDirectories: true)
            print("[VIDEO] Recording to \(sessionDir)")

            await glasses?.camera.startStream(resolution: .qvga, quality: .standard)

            fb.clear()
            TextRenderer.drawText("RECORDING...", x: 4, y: 4, on: fb)
            TextRenderer.drawText("[tap] stop", x: 4, y: fb.height - 10, on: fb)
            await glasses?.display.show(fb.pixels)
        } else {
            streaming = false
            await glasses?.camera.stop()

            let elapsed = (ContinuousClock.now - (startTime ?? .now)).durationSeconds
            let fps = elapsed > 0 ? Double(frameCount) / elapsed : 0

            print(String(format: "[VIDEO] Stopped. %d frames in %.1fs = %.2f fps",
                         frameCount, elapsed, fps))
            print("[VIDEO] Frames saved to: \(sessionDir)")
            print("[VIDEO] To make video: ffmpeg -framerate \(Int(fps.rounded())) -i \(sessionDir)/frame_%04d.jpg -c:v libx264 -pix_fmt yuv420p /tmp/seg-video.mp4")

            fb.clear()
            TextRenderer.drawText(
                String(format: "Stopped: %d frames", frameCount),
                x: 4, y: 20, on: fb)
            TextRenderer.drawText(
                String(format: "%.2f fps (%.1fs)", fps, elapsed),
                x: 4, y: 36, on: fb)
            TextRenderer.drawText("Saved: \(sessionDir)", x: 4, y: 52, on: fb)
            TextRenderer.drawText("[tap] restart", x: 4, y: fb.height - 10, on: fb)
            await glasses?.display.show(fb.pixels)
        }
    }

    func onSwipe(_ direction: InputEvent) async {}

    func onExit() async {
        if streaming { await glasses?.camera.stop() }
        glasses = nil
    }

    /// Called on each stream frame from GlassesDelegate.
    func onStreamFrame(_ data: Data) async {
        guard streaming else { return }
        frameCount += 1

        // Save JPEG frame to disk
        let filename = String(format: "%@/frame_%04d.jpg", sessionDir, frameCount)
        try? data.write(to: URL(fileURLWithPath: filename))

        // Update glasses display every 5th frame
        if frameCount % 5 == 0 {
            let elapsed = (ContinuousClock.now - (startTime ?? .now)).durationSeconds
            let fps = elapsed > 0 ? Double(frameCount) / elapsed : 0

            fb.clear()
            TextRenderer.drawText("REC", x: 4, y: 4, on: fb, value: 255)
            TextRenderer.drawText(
                String(format: "#%d  %.1f fps  %dB", frameCount, fps, data.count),
                x: 4, y: 24, on: fb)
            TextRenderer.drawText("[tap] stop", x: 4, y: fb.height - 10, on: fb)
            await glasses?.display.show(fb.pixels)
        }

        // Console log every 10th frame
        if frameCount % 10 == 0 {
            let elapsed = (ContinuousClock.now - (startTime ?? .now)).durationSeconds
            let fps = elapsed > 0 ? Double(frameCount) / elapsed : 0
            print(String(format: "[VIDEO] frame #%d  %.2f fps  %d bytes",
                         frameCount, fps, data.count))
        }
    }
}
