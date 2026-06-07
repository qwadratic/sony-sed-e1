import Foundation
import IOBluetooth

/// Bridges IOBluetooth RFCOMM delegate callbacks to the actor system.
/// Internal to SEGKit — extension apps never see this.
internal class BluetoothBridge: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private let transport: TransportActor
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onError: ((Int32) -> Void)?

    init(transport: TransportActor) {
        self.transport = transport
        super.init()
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                    status error: IOReturn) {
        if error == kIOReturnSuccess {
            Task { await transport.setBluetoothChannel(rfcommChannel) }
            onConnected?()
        } else {
            onError?(error)
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        onDisconnected?()
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                           data dataPointer: UnsafeMutableRawPointer!,
                           length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        Task { await transport.receiveBT(data) }
    }
}
