import SwiftUI

private struct TourSection: Identifiable {
    let title: String
    let summary: String
    let features: [Feature]
    var id: String { title }
}

struct GetStartedView: View {
    @ObservedObject var model: Model
    @ObservedObject var settings = Settings.shared
    let done: () -> Void
    @State private var name = "Focus"
    @State private var minutes = 30
    @State private var step = 0
    @State private var selected: Set<Feature> = []

    private let sections = [
        TourSection(title: "Focus session", summary: "Choose what happens while you work and when time is up.", features: [.blocking, .workspace, .pomodoro, .review, .notifications]),
        TourSection(title: "Plan your day", summary: "Add structure and reminders when you want them.", features: [.tasks, .scheduling, .guidance, .night]),
        TourSection(title: "Take control", summary: "Set limits around changing rules, stepping away, and starting Tartip.", features: [.settingsLock, .away, .login, .relaunch, .statistics]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if step == 0 {
                introduction
            } else if step == 1 {
                sessionSetup
            } else if step <= sections.count + 1 {
                featureChoices(sections[step - 2])
            }
            Spacer(minLength: 4)
            footer
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
        .onAppear {
            name = settings.value.activities.first?.name ?? "Focus"
            minutes = settings.value.defaultSessionMinutes
            selected = settings.value.features.enabled
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tartip guide")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("\(step + 1) of \(sections.count + 2)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text2)
                    .monospacedDigit()
            }
            ProgressView(value: Double(step + 1), total: Double(sections.count + 2))
                .tint(Theme.accent)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Make time for what matters", subtitle: "Tartip starts as a simple timer. You decide which extra tools to use.")
            guideCard(icon: "timer", title: "Start when you’re ready", detail: "Pick an activity and a length. The timer runs quietly until it ends or you stop it.")
            guideCard(icon: "slider.horizontal.3", title: "Add only what helps", detail: "Blocking, plans, reminders and other tools are optional. You can change these choices later in Settings.")
            Text("This short guide takes about a minute. Skip it any time.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
        }
    }

    private var sessionSetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Your first session", subtitle: "Start with one activity. You can add more from Activities later.")
            VStack(alignment: .leading, spacing: 14) {
                TextField("What are you focusing on?", text: $name)
                    .textFieldStyle(.roundedBorder)
                Picker("Session length", selection: $minutes) {
                    ForEach(Array(Set([15, 20, 30, 45, 60, settings.value.defaultSessionMinutes])).sorted(), id: \.self) {
                        Text("\($0) minutes").tag($0)
                    }
                }
            }
            .padding(16)
            .card(radius: 12)
            Text("Next, choose any tools you’d like to try. You can skip all of them.")
                .font(.system(size: 13)).foregroundStyle(Theme.text2)
        }
    }

    private func featureChoices(_ section: TourSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PageTitle(title: section.title, subtitle: section.summary)
            ScrollView {
                VStack(spacing: 9) {
                    ForEach(section.features) { feature in
                        featureRow(feature)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected.contains(feature) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(selected.contains(feature) ? Theme.accent : Theme.text2)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(feature.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(feature.title, isOn: Binding(
                get: { selected.contains(feature) },
                set: { enabled in
                    if enabled { selected.insert(feature) } else { selected.remove(feature) }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(12)
        .card(selected.contains(feature) ? Theme.accent : nil, radius: 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if selected.contains(feature) { selected.remove(feature) } else { selected.insert(feature) }
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip guide") {
                Setup.markDone()
                done()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text2)

            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.plain)
            }
            Spacer()
            if step < sections.count + 1 {
                Button("Continue") { step += 1 }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Start focus") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(.system(size: 13, weight: .medium))
    }

    private func guideCard(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card(radius: 12)
    }

    private func start() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !settings.value.activities.contains(where: { $0.name == title }) {
            if settings.value.activities.count == 1 && settings.value.activities[0].name == "Focus" {
                settings.value.activities[0].name = title
                settings.value.activities[0].block = title
            } else {
                settings.value.activities.append(ActivitySetting(name: title))
            }
        }
        settings.value.defaultMinutes = minutes
        settings.value.features = Features(enabled: selected)
        Setup.markDone()
        model.startActivity(title, minutes: minutes, pomodoro: false)
        done()
    }
}
