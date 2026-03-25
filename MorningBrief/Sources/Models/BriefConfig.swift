import Foundation

/// Gregorian weekday ordinal matching `Calendar.Component.weekday` (Sunday = 1 … Saturday = 7).
enum Weekday: Int, Codable, CaseIterable, Sendable {
  case sunday = 1
  case monday = 2
  case tuesday = 3
  case wednesday = 4
  case thursday = 5
  case friday = 6
  case saturday = 7

  var displayName: String {
    switch self {
    case .sunday: return "Sunday"
    case .monday: return "Monday"
    case .tuesday: return "Tuesday"
    case .wednesday: return "Wednesday"
    case .thursday: return "Thursday"
    case .friday: return "Friday"
    case .saturday: return "Saturday"
    }
  }
}

struct BriefConfig: Codable, Sendable, Equatable {
  var promptTemplate: String
  var scheduleHour: Int
  var notificationsEnabled: Bool
  var socialMonitoringEnabled: Bool
  var redditSearchQueries: [String]
  var hnSearchQueries: [String]
  var weeklyResetDay: Weekday
  var discordWebhookURL: String
  var discordRedditWebhookURL: String
  var discordHNWebhookURL: String

  var hasDiscordWebhook: Bool {
    !discordWebhookURL.trimmingCharacters(in: .whitespaces).isEmpty
  }

  static let `default` = BriefConfig(
    promptTemplate: defaultPromptTemplate,
    scheduleHour: 7,
    notificationsEnabled: true,
    socialMonitoringEnabled: true,
    redditSearchQueries: [
      "mac transcription app",
      "meeting transcription mac",
      "speech to text mac",
      "meeting recorder mac",
      "meeting assistant mac",
      "meeting summary app",
      "dictation app mac",
      "mimicscribe",
    ],
    hnSearchQueries: [
      "mac transcription",
      "meeting transcription",
      "meeting assistant AI",
      "speech to text local",
      "whisper transcription app",
      "meeting recorder",
      "mimicscribe",
    ],
    weeklyResetDay: .monday,
    discordWebhookURL: "",
    discordRedditWebhookURL: "",
    discordHNWebhookURL: ""
  )

  static func formattedHour(_ hour: Int) -> String {
    var components = DateComponents()
    components.hour = hour
    let date = Calendar.current.date(from: components) ?? Date()
    return hourFormatter.string(from: date)
  }

  private static let hourFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:00 a"
    return f
  }()

  private static var defaultPromptTemplate: String {
    guard let url = Bundle.module.url(forResource: "DefaultPrompt", withExtension: "md"),
      let content = try? String(contentsOf: url, encoding: .utf8)
    else {
      return "Generate a daily competitive intelligence briefing. Cite all sources with links."
    }
    return content
  }
}
