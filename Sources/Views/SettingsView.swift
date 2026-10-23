import SwiftUI
import AppKit

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @State private var newActivity = ""
    @State private var optionsText = Settings.shared.v.durationOptions.map(String.init).joined(separator: ", ")

    private let weekdays = [(2, "Mo"), (3, "Tu"), (4, "We"), (5, "Th"), (6, "Fr"), (7, "Sa"), (1, "Su")]

    var body: some View {
        ScrollView { content }
            .frame(width: 460, height: 640)
    }

    var content: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(.system(size: 20, weight: .bold, design: .rounded))
                activitiesSection
                guardSection
                nightSection
                freeTimeSection
                durationSection
                workspaceSection
                Text("Saved automatically to ~/modes/settings.json")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(22)
            .frame(width: 460)
    }

    // MARK: sections

    private var activitiesSection: some View {
        group("Activities · daily limit", "Each activity starts the Cold Turkey block with the same name. When today's limit is used up, it disappears from the picker.") {
            ForEach($settings.v.activities) { $a in
                let st = ActivityStyle.of(a.name)
                HStack(spacing: 8) {
                    Image(systemName: st.icon).foregroundStyle(st.color).frame(width: 18)
                    TextField("Name", text: $a.name).textFieldStyle(.plain).font(.system(size: 13))
                    Spacer()
                    Text(limitLabel(a.dailyMinutes))
                        .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(a.dailyMinutes == 0 ? .secondary : .primary)
                        .frame(width: 66, alignment: .trailing)
                    Stepper("", value: $a.dailyMinutes, in: 0...720, step: 15).labelsHidden().controlSize(.small)
                    Button { settings.v.activities.removeAll { $0.id == a.id } } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .card(radius: 9)
            }
            HStack(spacing: 6) {
                TextField("New activity (same name as its Cold Turkey block)", text: $newActivity)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .card(radius: 9)
                    .onSubmit(addActivity)
                Button("Add", action: addActivity)
                    .disabled(newActivity.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var guardSection: some View {
        group("Guard", "When idle time counts and the \(settings.v.idleNudgeMinutes)-minute prompt can appear.") {
            HStack(spacing: 4) {
                ForEach(weekdays, id: \.0) { wd, label in
                    let on = settings.v.guardDays.contains(wd)
                    Button {
                        if on { settings.v.guardDays.removeAll { $0 == wd } } else { settings.v.guardDays.append(wd) }
                    } label: {
                        Text(label).font(.system(size: 12, weight: on ? .semibold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(Capsule().fill(on ? AnyShapeStyle(Color.indigo.gradient) : AnyShapeStyle(.quaternary.opacity(0.6))))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            row("From") { hourStepper($settings.v.guardFromHour) }
            row("To") { hourStepper($settings.v.guardToHour) }
        }
    }

    private var nightSection: some View {
        group("Night", "Nothing is asked and no timers run; the night block stays on so you go to sleep.") {
            Toggle("Night mode", isOn: $settings.v.nightEnabled).toggleStyle(.switch).controlSize(.small)
            if settings.v.nightEnabled {
                row("From") { clockStepper($settings.v.nightFrom) }
                row("To") { clockStepper($settings.v.nightTo) }
                row("Cold Turkey block") { textField($settings.v.nightBlock) }
            }
        }
    }

    private var freeTimeSection: some View {
        group("Free time", "Rest (☕) and idle time at the computer share one daily budget.") {
            row("Per day") { minuteStepper($settings.v.dailyFreeMinutes, 0...240, step: 5) }
            row("One rest at most") { minuteStepper($settings.v.maxRestMinutes, 5...60, step: 5) }
            row("Prompt after idle") { minuteStepper($settings.v.idleNudgeMinutes, 5...60, step: 5) }
            row("Prompt countdown") {
                HStack(spacing: 6) {
                    Text("\(settings.v.promptCountdownSeconds) s").monospacedDigit()
                    Stepper("", value: $settings.v.promptCountdownSeconds, in: 10...300, step: 10).labelsHidden()
                }
            }
        }
    }

    private var durationSection: some View {
        group("Session length", nil) {
            row("Options (min)") {
                TextField("15, 20, 30, 45, 60", text: $optionsText)
                    .textFieldStyle(.roundedBorder).frame(width: 160)
                    .onSubmit(saveOptions)
                    .onChange(of: optionsText) { _ in saveOptions() }
            }
            row("Default") { minuteStepper($settings.v.defaultMinutes, 5...240, step: 5) }
            row("Minimum") { minuteStepper($settings.v.minMinutes, 5...120, step: 5) }
            row("Pomodoro work") { minuteStepper($settings.v.pomodoroWork, 5...90, step: 5) }
            row("Pomodoro break") { minuteStepper($settings.v.pomodoroBreak, 1...30, step: 1) }
            row("Pomodoro rounds") {
                HStack(spacing: 6) {
                    Text("\(settings.v.pomodoroRounds)").monospacedDigit()
                    Stepper("", value: $settings.v.pomodoroRounds, in: 1...8).labelsHidden()
                }
            }
        }
    }

    private var workspaceSection: some View {
        group("Workspace", nil) {
            row("Open on desktop") {
                HStack(spacing: 6) {
                    Text(settings.v.desktop == 0 ? "current" : "\(settings.v.desktop)").monospacedDigit()
                    Stepper("", value: $settings.v.desktop, in: 0...9).labelsHidden()
                }
            }
            row("Block for \"Other\"") { textField($settings.v.otherBlock) }
        }
    }

    // MARK: building blocks

    private func group<Content: View>(_ title: String, _ note: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            if let note { Text(note).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            content()
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            content().font(.system(size: 13))
        }
    }

    private func minuteStepper(_ value: Binding<Int>, _ range: ClosedRange<Int>, step: Int) -> some View {
        HStack(spacing: 6) {
            Text(limitLabel(value.wrappedValue) == "No limit" ? "0m" : limitLabel(value.wrappedValue)).monospacedDigit()
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
    }

    private func hourStepper(_ value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(String(format: "%02d:00", value.wrappedValue)).monospacedDigit()
            Stepper("", value: value, in: 0...24).labelsHidden()
        }
    }

    // Half-hour steps, wrapping around midnight.
    private func clockStepper(_ value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(clockLabel(value.wrappedValue)).monospacedDigit()
            Stepper("", onIncrement: { value.wrappedValue = (value.wrappedValue + 30) % 1440 },
                        onDecrement: { value.wrappedValue = (value.wrappedValue + 1410) % 1440 }).labelsHidden()
        }
    }

    private func textField(_ value: Binding<String>) -> some View {
        TextField("", text: value).textFieldStyle(.roundedBorder).frame(width: 160)
    }

    private func addActivity() {
        let n = newActivity.trimmingCharacters(in: .whitespaces)
        newActivity = ""
        guard !n.isEmpty, !settings.v.activities.contains(where: { $0.name.lowercased() == n.lowercased() }) else { return }
        settings.v.activities.append(ActivitySetting(name: n))
    }

    private func saveOptions() {
        let list = optionsText.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) }.filter { $0 > 0 }
        if !list.isEmpty { settings.v.durationOptions = Array(Set(list)).sorted() }
    }
}
