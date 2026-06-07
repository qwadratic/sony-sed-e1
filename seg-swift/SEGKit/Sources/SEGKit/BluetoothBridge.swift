import Foundation
import IOBluetooth

/// Bridges IOBluetooth RFCOMM delegate callbacks to the actor system.
/// Internal to SEGKit — extension apps never see this.
///
/// IOBluetooth requires all operations on the main RunLoop thread.
/// This bridge handles the main-thread requirement and hops to actors via Task.
internal class BluetoothBridge: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private let transport: TransportActor
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onError: ((Int32) -> Void)?
    var eventLog: EventLogger?

    init(transport: TransportActor) {
        self.transport = transport
        super.init()
    }

    private var channelOpened = false
    
    /// Open RFCOMM channel and wait for the open-complete callback.
    /// Pumps the RunLoop to allow IOBluetooth to process the connection.
    func openChannel(device: IOBluetoothDevice, channelID: BluetoothRFCOMMChannelID,
                     timeout: TimeInterval = 15) -> IOReturn {
        channelOpened = false
        var channel: IOBluetoothRFCOMMChannel? = nil
        
        // First establish baseband connection (handles pairing if needed)
        let connResult = device.openConnection()
        eventLog?.debug("openConnection result=\(connResult) connected=\(device.isConnected())", minLevel: .normal)
        
        let result = device.openRFCOMMChannelAsync(&channel, withChannelID: channelID, delegate: self)
        eventLog?.debug("openRFCOMMChannelAsync result=\(result) channel=\(channel != nil)", minLevel: .normal)
        
        guard result == kIOReturnSuccess else { return result }
        
        // Pump RunLoop until callback fires or timeout
        let deadline = Date().addingTimeInterval(timeout)
        while !channelOpened && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        
        if channelOpened {
            eventLog?.debug("RFCOMM channel opened successfully", minLevel: .normal)
        } else {
            eventLog?.debug("RFCOMM channel open timed out after \(timeout)s", minLevel: .normal)
        }
        
        return channelOpened ? kIOReturnSuccess : kIOReturnTimeout
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                    status error: IOReturn) {
        eventLog?.debug("rfcommChannelOpenComplete status=\(error) mtu=\(rfcommChannel?.getMTU() ?? 0)", minLevel: .normal)
        if error == kIOReturnSuccess {
            channelOpened = true
            Task { await transport.setBluetoothChannel(rfcommChannel) }
            onConnected?()
        } else {
            eventLog?.debug("RFCOMM open failed: \(error)", minLevel: .normal)
            onError?(error)
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        eventLog?.debug("rfcommChannelClosed", minLevel: .normal)
        onDisconnected?()
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                           data dataPointer: UnsafeMutableRawPointer!,
                           length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        Task { await transport.receiveBT(data) }
    }
}
