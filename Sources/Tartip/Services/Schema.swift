import Foundation

// ~/modes/logs/SCHEMA.md: what the files mean, for analysis outside the app (DuckDB, pandas,
// Numbers, an AI). Rewritten at launch when it differs, so it always matches this version.
func writeSchema() {
    if (try? String(contentsOf: schemaFile, encoding: .utf8)) == schema { return }
    try? FileManager.default.createDirectory(at: schemaFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? schema.write(to: schemaFile, atomically: true, encoding: .utf8)
}

private let schema = """
# Tärtip data

One JSON object per line. Times are ISO 8601 in UTC (`2026-10-28T16:40:00Z`); durations are
whole seconds unless the name says minutes. A field that's missing means "not known": older
lines were written before it existed. Lines can be edited or removed by hand; the app reads
whatever is there.

## sessions.jsonl: one line per reviewed session

This is the one record of time spent: limits and Stats count from it.

| Field | Meaning |
|---|---|
| `start` | When the time counted starts: the real start moved later by the time away (`began` + `paused`). `end` − `start` is the time spent. |
| `end` | When it ended: done, stopped, or when you left if you were away too long. |
| `mode` | The block that was on. |
| `planned` | The activity picked. |
| `actual` | What you said you did at the review. Empty: not reviewed. Several: the time is split evenly. |
| `note` | Old lines only. |
| `began` | When it really started, by the clock. |
| `plannedMinutes` | The length it was started with, Pomodoro breaks included. |
| `rounds` | Pomodoro work rounds, when more than one. |
| `paused` | Seconds away from the computer in the middle of it. |
| `ended` | `done` (time ran out), `stopped` (Stop session; the block stays on until its time anyway), `away` (away longer than the limit in Rules; ends as of when you left). |
| `auto` | `true`: started by itself after "What's next?" went unanswered. |
| `pickSeconds` | Seconds from "What's next?" opening to the start. Missing when started from the panel, or when you stepped away in between. |

Sessions under a minute aren't recorded.

## away.jsonl: one line per stretch away from the computer

`start`, `end`. Locking the screen and sleep count too, so stretches overnight are sleep.
Not an activity: never counted in limits.

## events.jsonl: things that aren't sessions

Every line has `t` (when it happened) and `type`:

| `type` | Fields |
|---|---|
| `free` | A piece of free time. `t` is when it started, `minutes` the length taken, `seconds` the time actually used (less when ended early). |
| `blocked` | A blocked app was quit or a blocked site was sent to "Not now". `name` is the app's bundle id or the site's host (never the page), `block` the block that caught it. Counted once per app or site per lock. |
| `round` | Every limit was used up or closed, so they started over. `number` is the day's round that began. |

## modes.log

Human-readable event log in local time. Its wording may change between versions; use the
files above for analysis.
"""
