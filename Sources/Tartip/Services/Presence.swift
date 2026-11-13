import CoreGraphics
import Foundation
import IOKit.pwr_mgt

// ~0 is kCGAnyInputEventType: the last input of any kind.
func secondsSinceInput() -> TimeInterval {
    guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
}

// At the computer: input in the last 2 minutes, or watching something, and screen not locked.
func userPresent() -> Bool {
    (secondsSinceInput() <= 120 || watching()) && !screenLocked()
}

// A video (or a call) is playing: the app showing it keeps the display awake, so there's no
// input but you're still here. Our own KeepAwake holds system sleep only, so it doesn't count.
func watching() -> Bool {
    var status: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
          let counts = status?.takeRetainedValue() as? [String: Any]
    else { return false }
    return [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypeNoDisplaySleep]
        .contains { (counts[$0] as? Int ?? 0) > 0 }
}

func screenLocked() -> Bool {
    (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
}
