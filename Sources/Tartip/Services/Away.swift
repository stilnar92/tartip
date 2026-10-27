import Foundation
import IOKit.pwr_mgt

// Away from the computer: the screen is locked so it can't be used, but the Mac stays awake,
// so scripts, builds and downloads left running carry on.

// Locks the screen now, as the Lock Screen menu item does. The call lives in a private
// framework; if it's missing, the display goes to sleep instead (which locks when a password
// is required right away).
func lockScreen() {
    if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
       let sym = dlsym(h, "SACLockScreenImmediate") {
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(sym, to: Lock.self)()
        return
    }
    run("/usr/bin/pmset", ["displaysleepnow"])
}

// Keeps the system from sleeping while idle; the display may still turn off.
@MainActor
final class KeepAwake {
    private var assertion: IOPMAssertionID = 0
    private(set) var isOn = false

    func on() {
        guard !isOn else { return }
        isOn = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "Tartip: away, keeping your tasks running" as CFString, &assertion) == kIOReturnSuccess
    }

    func off() {
        guard isOn else { return }
        IOPMAssertionRelease(assertion)
        isOn = false
    }
}
