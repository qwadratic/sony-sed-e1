import Foundation

/// Input event API for extension apps.
public final class InputSubsystem: @unchecked Sendable {
    internal init() {}
    
    /// Parse a LayoutEventNotify (0xe5) or LevelNotification (0x06) into an InputEvent.
    /// Wire format: 0xe5 payload = [eventType: 2B LE] [resultStateId: 2B LE]
    /// Event types from LayoutEventType.smali decompilation.
    internal func parseEvent(cmdId: UInt8, payload: Data) -> InputEvent? {
        switch cmdId {
        case 0x06:  // LevelNotification — treated as tap
            return .tap
        case 0xe5:  // LayoutEventNotify
            guard payload.count >= 2 else { return nil }
            // eventType is a 16-bit value, but all known types fit in first byte
            let eventType = payload[0]
            switch eventType {
            // Jog dial
            case 0x01: return .jogPress
            case 0x02: return .jogLongPress
            case 0x03: return .jogLongRelease
            case 0x04: return .jogRotateCW
            case 0x05: return .jogRotateCCW
            
            // Hardware buttons
            case 0x08: return .backButton
            case 0x09: return .cameraButton
            case 0x0a: return .backLongPress
            case 0x0b: return .pttPress
            case 0x0c: return .pttRelease
            
            // Display
            case 0x0d: return .displayOff
            case 0x0e: return .displayOn
            case 0x0f: return .cameraLongPress
            
            // Touchpad
            case 0x10: return .fingerOff
            case 0x11: return .fingerOn
            case 0x12: return .tap
            case 0x13: return .longPress
            case 0x14: return .swipeLeft
            case 0x15: return .swipeRight
            
            default: return .unknown(code: eventType)
            }
        default:
            return nil
        }
    }
}
