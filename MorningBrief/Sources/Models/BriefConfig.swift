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

struct BriefConfig: Sendable, Equatable {
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
  var competitors: [String]

  var hasDiscordWebhook: Bool {
    !discordWebhookURL.trimmingCharacters(in: .whitespaces).isEmpty
  }
}

// Decode resiliently — unknown keys in config.json are silently ignored,
// and missing keys fall back to defaults so the app never loses settings.
extension BriefConfig: Codable {
  enum CodingKeys: String, CodingKey {
    case promptTemplate, scheduleHour, notificationsEnabled
    case socialMonitoringEnabled, redditSearchQueries, hnSearchQueries
    case weeklyResetDay, discordWebhookURL, discordRedditWebhookURL, discordHNWebhookURL
    case competitors
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = BriefConfig.default
    promptTemplate = (try? c.decode(String.self, forKey: .promptTemplate)) ?? d.promptTemplate
    scheduleHour = (try? c.decode(Int.self, forKey: .scheduleHour)) ?? d.scheduleHour
    notificationsEnabled = (try? c.decode(Bool.self, forKey: .notificationsEnabled)) ?? d.notificationsEnabled
    socialMonitoringEnabled = (try? c.decode(Bool.self, forKey: .socialMonitoringEnabled)) ?? d.socialMonitoringEnabled
    redditSearchQueries = (try? c.decode([String].self, forKey: .redditSearchQueries)) ?? d.redditSearchQueries
    hnSearchQueries = (try? c.decode([String].self, forKey: .hnSearchQueries)) ?? d.hnSearchQueries
    weeklyResetDay = (try? c.decode(Weekday.self, forKey: .weeklyResetDay)) ?? d.weeklyResetDay
    discordWebhookURL = (try? c.decode(String.self, forKey: .discordWebhookURL)) ?? d.discordWebhookURL
    discordRedditWebhookURL = (try? c.decode(String.self, forKey: .discordRedditWebhookURL)) ?? d.discordRedditWebhookURL
    discordHNWebhookURL = (try? c.decode(String.self, forKey: .discordHNWebhookURL)) ?? d.discordHNWebhookURL
    competitors = (try? c.decode([String].self, forKey: .competitors)) ?? d.competitors
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
    discordHNWebhookURL: "",
    competitors: [
      "MacWhisper",
      "Granola",
      "Talat",
      "BB Recorder",
      "Otter.ai",
      "Fireflies.ai",
      "Krisp",
      "Fathom",
      "tl;dv",
      "Notta",
      "Tactiq",
      "Supernormal",
      "Rev",
      "Whisper Transcription",
    ]
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
