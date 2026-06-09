import SEGKit

/// Base protocol for all demos. Extension apps define demos using only SEGKit public API.
/// This is equivalent of Sony's BaseDemo abstract class.
public protocol Demo: AnyObject {
    var name: String { get }
    
    /// Called when demo becomes active. Set up state, start timers.
    func onEnter(glasses: GlassesConnection) async
    
    /// Called on user tap.
    func onTap() async
    
    /// Called on user swipe.
    func onSwipe(_ direction: InputEvent) async
    
    /// Called when demo exits. Clean up timers, release camera.
    func onExit() async
}
