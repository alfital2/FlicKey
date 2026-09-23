import AppKit
import CoreGraphics

// Separate FlicKey's generated edit keys from physical keys (including keys
// replayed after a protected edit). The delivery token also lets the barrier
// wait until the last generated event has passed its tap before replay begins.
enum SyntheticEventMarker {
    private static let value: Int64 = 0x464C49434B4559
    private static let deliveryPrefix: Int64 = 0x464C440000000000

    static func newDeliveryToken() -> Int64 {
        deliveryPrefix | Int64(UInt32.random(in: 1...UInt32.max))
    }

    static func mark(_ event: CGEvent?, token: Int64? = nil) {
        event?.setIntegerValueField(.eventSourceUserData, value: token ?? value)
    }

    static func retag(_ event: CGEvent, using source: CGEventSource) {
        event.setIntegerValueField(.eventSourceUserData, value: source.userData)
        if event.getIntegerValueField(.eventSourceUserData) != source.userData {
            source.keyboardType = CGEventSourceKeyboardType(event.getIntegerValueField(.keyboardEventKeyboardType))
            event.setSource(source)
        }
    }

    static func isMarked(_ event: CGEvent) -> Bool {
        let tag = event.getIntegerValueField(.eventSourceUserData)
        return tag == value || tag & 0x7FFFFFFF00000000 == deliveryPrefix
    }

    static func isMarked(_ event: NSEvent) -> Bool {
        guard let event = event.cgEvent else { return false }
        return isMarked(event)
    }
}
