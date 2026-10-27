import Foundation

// Everything personal lives in ~/modes, outside the repo.
let modesDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("modes")
let settingsFile = modesDir.appendingPathComponent("settings.json")
let configFile = modesDir.appendingPathComponent("modes.json")   // old; moved into settings.json
let sessionsFile = modesDir.appendingPathComponent("logs/sessions.jsonl")
let awayFile = modesDir.appendingPathComponent("logs/away.jsonl")       // time away from the computer
let logFile = modesDir.appendingPathComponent("logs/modes.log")
