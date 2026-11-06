import CoreGraphics
import Foundation

// ~0 is kCGAnyInputEventType: the last input of any kind.
func secondsSinceInput() -> TimeInterval {
    guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
}

// At the computer: input in the last 2 minutes and screen not locked.
func userPresent() -> Bool {
    secondsSinceInput() <= 120 && !screenLocked()
}

func screenLocked() -> Bool {
    (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
}
