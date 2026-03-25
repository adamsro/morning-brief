import Foundation
import OSLog

private let logger = Logger(subsystem: "com.morningbrief.app", category: "ConfigService")

@MainActor
final class ConfigService {
  static let shared = ConfigService()

  var config: BriefConfig = .default

  private static var configFileURL: URL {
    StorageService.appSupportDirectoryURL.appendingPathComponent("config.json")
  }

  func load() {
    let url = Self.configFileURL
    guard FileManager.default.fileExists(atPath: url.path) else {
      config = .default
      return
    }
    do {
      let data = try Data(contentsOf: url)
      config = try JSONDecoder().decode(BriefConfig.self, from: data)
    } catch {
      // Config file exists but is unreadable or corrupt — reset to defaults so
      // the app remains usable rather than failing to launch.
      logger.warning("Failed to load config, resetting to defaults: \(error)")
      config = .default
    }
  }

  func save() throws {
    let url = Self.configFileURL
    try FileManager.default.createDirectory(
      at: StorageService.appSupportDirectoryURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    try data.write(to: url)
  }

  var systemPrompt: String {
    "You are a competitive intelligence assistant. Your job is to find actionable information — "
      + "things the user can DO today, not just things to read about. "
      + "Search the web thoroughly. Every claim must include a source URL. "
      + "If someone on Reddit or HN is asking for a tool like the user's product, that's the #1 priority — "
      + "give the URL and a suggested reply angle. "
      + "Keep briefs short and action-oriented. A 20-line brief with real action items beats a 200-line report."
  }

  private static let promptDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEEE, MMMM dd, yyyy"
    return f
  }()

  /// Build the prompt with social context. Picks Monday (deep dive) vs daily (delta) variant.
  func buildPrompt(socialPosts: [SocialMonitorService.SocialPost], isMonday: Bool) -> String {
    let dateString = Self.promptDateFormatter.string(from: Date())
    let dayType = isMonday ? "MONDAY — do a broader weekly competitive landscape scan." : ""

    var prompt = config.promptTemplate
      .replacingOccurrences(of: "{{DATE}}", with: dateString)
      .replacingOccurrences(of: "{{DAY_TYPE}}", with: dayType)

    if !socialPosts.isEmpty {
      let capped = Array(socialPosts.prefix(20))
      prompt += "\n\n<SOCIAL_CONTEXT>\n"
      prompt +=
        "Real-time posts from Reddit and Hacker News (last 24 hours). "
      prompt +=
        "These are verified, real posts — not from a web search. "
      prompt +=
        "If anyone is asking for a tool like MimicScribe, that's a DO TODAY item.\n\n"

      for post in capped {
        let sourceLabel: String
        if post.source == "reddit", let sub = post.subreddit {
          sourceLabel = "reddit/r/\(sub)"
        } else {
          sourceLabel = post.source
        }
        prompt +=
          "[\(sourceLabel)] \"\(post.title)\" (score: \(post.score), \(post.commentCount) comments) — \(post.url)\n"
        if !post.snippet.isEmpty {
          prompt += "  > \(post.snippet)\n"
        }
      }
      prompt += "\n</SOCIAL_CONTEXT>\n"
    }

    return prompt
  }
}
