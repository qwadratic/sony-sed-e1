import Foundation

/// Input event API for extension apps.
public final class InputSubsystem: @unchecked Sendable {
    internal init() {}
    
    /// Parse a LayoutEventNotify (0xe5) or LevelNotification (0x06) into an InputEvent.
    internal func parseEvent(cmdId: UInt8, payload: Data) -> InputEvent? {
        switch cmdId {
        case 0x06:  // LevelNotification — treated as tap
            return .tap
        case 0xe5:  // LayoutEventNotify
            guard payload.count >= 2 else { return nil }
            let action = payload[0]
            switch action {
            case 0x00: return .tap
            case 0x01: return .longPress
            case 0x03: // swipe
                guard payload.count >= 2 else { return nil }
                switch payload[1] {
                case 0x01: return .swipeLeft
                case 0x02: return .swipeRight
                case 0x03: return .swipeUp
                case 0x04: return .swipeDown
                default: return nil
                }
            default: return nil
            }
        default:
            return nil
        }
    }
}
