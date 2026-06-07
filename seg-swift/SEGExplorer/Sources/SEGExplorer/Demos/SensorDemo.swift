import SEGKit

/// Sensors: Live — accelerometer + gyroscope readout.
final class SensorDemo: Demo {
    let name = "Sensors: Live"
    private var glasses: GlassesConnection?
    private let fb = FrameBuffer()
    private var mockMode = false
    private var lastReading = SensorReading()
    
    func onEnter(glasses: GlassesConnection) async {
        self.glasses = glasses
        lastReading = SensorReading(
            accelerometer: SIMD3<Float>(0, 9.81, 0),
            gyroscope: .zero
        )
        // Start sensor streams from glasses hardware
        await glasses.sensors.start(.accelerometer)
        await glasses.sensors.start(.gyroscope)
        await glasses.sensors.start(.magnetometer)
        await render()
    }
    
    func onTap() async {
        mockMode.toggle()
        if mockMode {
            lastReading = SensorReading(
                accelerometer: SIMD3<Float>(0.12, 9.81, 0.34),
                gyroscope: SIMD3<Float>(0.01, -0.02, 0.00)
            )
        }
        await render()
    }
    
    func onSwipe(_ direction: InputEvent) async {}
    func onExit() async {
        await glasses?.sensors.stop(.accelerometer)
        await glasses?.sensors.stop(.gyroscope)
        await glasses?.sensors.stop(.magnetometer)
        glasses = nil
    }
    
    /// Called by the app controller when sensor data arrives from GlassesDelegate.
    func updateSensorData(_ reading: SensorReading) async {
        guard !mockMode else { return }
        lastReading = reading
        await render()
    }
    
    private func render() async {
        fb.clear()
        let mode = mockMode ? "MOCK" : "LIVE"
        TextRenderer.drawText("SENSORS [\(mode)]", x: 4, y: 4, on: fb)
        fb.drawHLine(x: 0, y: 14, length: fb.width, value: 128)
        
        let a = lastReading.accelerometer
        TextRenderer.drawText(
            String(format: "Accel  x:%+.2f y:%+.2f z:%+.2f", a.x, a.y, a.z),
            x: 4, y: 22, on: fb
        )
        
        let g = lastReading.gyroscope
        TextRenderer.drawText(
            String(format: "Gyro   x:%+.2f y:%+.2f z:%+.2f", g.x, g.y, g.z),
            x: 4, y: 38, on: fb
        )
        
        let m = lastReading.magnetometer
        TextRenderer.drawText(
            String(format: "Mag    x:%+.2f y:%+.2f z:%+.2f", m.x, m.y, m.z),
            x: 4, y: 54, on: fb
        )
        
        TextRenderer.drawText("[tap] toggle mock", x: 4, y: fb.height - 10, on: fb)
        await glasses?.display.show(fb.pixels)
    }
}
