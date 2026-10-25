import CoreGraphics

// At the computer: input in the last 2 minutes and screen not locked.
func userPresent() -> Bool {
    // ~0 is kCGAnyInputEventType: the last input of any kind.
    if let anyInput = CGEventType(rawValue: ~0),
       CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) > 120 { return false }
    if let d = CGSessionCopyCurrentDictionary() as? [String: Any], d["CGSSessionScreenIsLocked"] as? Bool == true { return false }
    return true
}
