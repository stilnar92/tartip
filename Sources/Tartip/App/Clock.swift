import Foundation
import Combine

// The current time, updated every second by the model's tick. Only views that show a
// countdown observe it, so the main window doesn't redraw every second.
@MainActor
final class Clock: ObservableObject {
    @Published var now = Date()
}
