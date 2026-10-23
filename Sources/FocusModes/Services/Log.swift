import Foundation

// The event log, ~/modes/logs/modes.log. Called from any thread; writes go through one queue.
private let logQueue = DispatchQueue(label: "log")

func log(_ line: String) {
    let text = "\(Fmt.logStamp.string(from: Date())) \(line)\n"
    logQueue.async { appendText(text, to: logFile) }
}

// Appends to a file, creating it and its folder when needed. Failures go to stderr,
// since the log itself may be what can't be written.
@discardableResult
func appendText(_ text: String, to url: URL) -> Bool {
    let fm = FileManager.default
    do {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
        return true
    } catch {
        FileHandle.standardError.write(Data("can't write \(url.path): \(error)\n".utf8))
        return false
    }
}
