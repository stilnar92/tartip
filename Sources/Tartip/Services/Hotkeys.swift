import Carbon.HIToolbox

// Shortcuts that work from any app. Carbon's hot keys need no permission (unlike watching
// every key press), and the key is taken only while Tartip runs.

struct Hotkey {
    let key: Int          // kVK_ code
    let label: String     // as shown in Rules
    let name: String
    let action: @MainActor () -> Void
}

private let modifiers = UInt32(controlKey | optionKey | cmdKey)

@MainActor
final class Hotkeys {
    static let shared = Hotkeys()
    private(set) var all: [Hotkey] = []
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    func register(_ keys: [Hotkey]) {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        if let handler { RemoveEventHandler(handler) }
        all = keys
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { Hotkeys.shared.fire(Int(id.id)) }
            return noErr
        }, 1, &spec, nil, &handler)
        for (i, k) in keys.enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(k.key), modifiers, EventHotKeyID(signature: OSType(0x54727470), id: UInt32(i)),
                                             GetApplicationEventTarget(), 0, &ref)
            if let ref { refs.append(ref) } else { log("hotkey \(k.label) not available (\(status))") }
        }
    }

    private func fire(_ i: Int) {
        guard all.indices.contains(i) else { return }
        log("hotkey \(all[i].label) \(all[i].name)")
        all[i].action()
    }
}
