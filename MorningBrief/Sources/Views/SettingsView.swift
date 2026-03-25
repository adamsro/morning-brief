import OSLog
import ServiceManagement
import SwiftUI

private let logger = Logger(subsystem: "com.morningbrief.app", category: "SettingsView")

struct SettingsView: View {
  @Environment(AppState.self) private var appState
  @State private var config: BriefConfig = .default
  @State private var launchAtLogin = false
  @State private var saveTask: Task<Void, Never>?

  private static let weekdays: [Weekday] = [
    .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
  ]

  private var redditQueriesBinding: Binding<String> {
    Binding(
      get: { config.redditSearchQueries.joined(separator: "\n") },
      set: { newValue in
        config.redditSearchQueries = newValue.split(
          separator: "\n", omittingEmptySubsequences: true
        )
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
      }
    )
  }

  private var hnQueriesBinding: Binding<String> {
    Binding(
      get: { config.hnSearchQueries.joined(separator: "\n") },
      set: { newValue in
        config.hnSearchQueries = newValue.split(separator: "\n", omittingEmptySubsequences: true)
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty }
      }
    )
  }

  var body: some View {
    Form {
      Section("Schedule") {
        Picker("Generate at", selection: $config.scheduleHour) {
          ForEach(0..<24, id: \.self) { hour in
            Text(BriefConfig.formattedHour(hour)).tag(hour)
          }
        }
        Picker("Weekly reset", selection: $config.weeklyResetDay) {
          ForEach(Self.weekdays, id: \.self) { day in
            Text(day.displayName).tag(day)
          }
        }
        .help("Start a fresh session on this day for a broader weekly scan")
      }

      Section("Discord") {
        TextField("#morning-brief webhook", text: $config.discordWebhookURL)
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
        TextField("#reddit-mentions webhook", text: $config.discordRedditWebhookURL)
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
        TextField("#hn-mentions webhook", text: $config.discordHNWebhookURL)
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
        Text("Create webhooks in Discord: channel → Edit → Integrations → Webhooks")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Section("Behavior") {
        Toggle("Notifications", isOn: $config.notificationsEnabled)
        Toggle("Launch at Login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, newValue in
            toggleLoginItem(newValue)
          }
        Toggle("Social monitoring (Reddit & HN)", isOn: $config.socialMonitoringEnabled)
          .help("Fetch recent Reddit and Hacker News posts to include as context")
      }

      if config.socialMonitoringEnabled {
        Section("Search Queries") {
          Text("Reddit searches (one per line):")
            .font(.callout)
            .foregroundStyle(.secondary)
          TextEditor(text: redditQueriesBinding)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 80)

          Text("Hacker News searches (one per line):")
            .font(.callout)
            .foregroundStyle(.secondary)
          TextEditor(text: hnQueriesBinding)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 80)

          Button("Reset to Defaults") {
            config.redditSearchQueries = BriefConfig.default.redditSearchQueries
            config.hnSearchQueries = BriefConfig.default.hnSearchQueries
          }
        }
      }

      Section("Prompt") {
        Text(
          "Sent to Claude Code to generate your brief. Use {{DATE}} for today's date, {{DAY_TYPE}} for Monday deep-dive flag."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        TextEditor(text: $config.promptTemplate)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 250)

        Button("Reset Prompt to Default") {
          config.promptTemplate = BriefConfig.default.promptTemplate
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      config = ConfigService.shared.config
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    .onChange(of: config) {
      scheduleSave()
    }
  }

  // Debounce saves so rapid keystrokes (e.g. editing the prompt) don't cause a
  // disk write per character. Picker and toggle changes still commit within 0.5s.
  private func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      ConfigService.shared.config = config
      do {
        try ConfigService.shared.save()
      } catch {
        logger.warning("Failed to save config: \(error)")
      }
    }
  }

  private func toggleLoginItem(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }
}
