import Foundation

struct SessionInfo: Codable, Sendable {
  var sessionId: String
  var weekStartDate: Date
  var dayCount: Int
}

@MainActor
final class StorageService {
  static let shared = StorageService()

  static let appSupportDirectoryURL: URL = {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
        "Library/Application Support")
    return base.appendingPathComponent("com.morningbrief.app")
  }()

  private static let reportsDirectoryURL: URL = {
    let docs =
      FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
    return docs.appendingPathComponent("Morning Brief")
  }()

  private static let metadataDirectoryURL: URL = {
    appSupportDirectoryURL.appendingPathComponent("metadata")
  }()

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private static let lastRunKey = "lastRunDate"

  private static var sessionFileURL: URL {
    appSupportDirectoryURL.appendingPathComponent("session.json")
  }

  private static var seenPostsFileURL: URL {
    appSupportDirectoryURL.appendingPathComponent("seen-posts.json")
  }

  private static let lastSocialRunKey = "lastSocialRunDate"

  // MARK: - Reports

  func saveReport(markdown: String, sessionId: String, duration: Double) throws -> ReportMetadata {
    let today = Self.dateFormatter.string(from: Date())
    let fileName = "\(today).md"

    try FileManager.default.createDirectory(
      at: Self.reportsDirectoryURL, withIntermediateDirectories: true)
    let reportURL = Self.reportsDirectoryURL.appendingPathComponent(fileName)
    try markdown.write(to: reportURL, atomically: true, encoding: .utf8)

    let metadata = ReportMetadata(
      date: Date(),
      reportPath: reportURL.path,
      generationDurationSeconds: duration,
      sessionId: sessionId
    )
    try FileManager.default.createDirectory(
      at: Self.metadataDirectoryURL, withIntermediateDirectories: true)
    let metadataURL = Self.metadataDirectoryURL.appendingPathComponent("\(today).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(metadata).write(to: metadataURL)

    return metadata
  }

  /// Load the most recent report metadata, checking today and up to 7 days back.
  func loadLatestMetadata() -> ReportMetadata? {
    let calendar = Calendar.current
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    for dayOffset in 0...7 {
      guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else {
        continue
      }
      let dateStr = Self.dateFormatter.string(from: date)
      let metadataURL = Self.metadataDirectoryURL.appendingPathComponent("\(dateStr).json")
      if let data = try? Data(contentsOf: metadataURL),
        let metadata = try? decoder.decode(ReportMetadata.self, from: data)
      {
        return metadata
      }
    }
    return nil
  }

  func loadReportContent(at path: String) -> String? {
    try? String(contentsOfFile: path, encoding: .utf8)
  }

  // MARK: - Session Management

  func saveSession(_ session: SessionInfo) throws {
    try FileManager.default.createDirectory(
      at: Self.appSupportDirectoryURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(session)
    try data.write(to: Self.sessionFileURL)
  }

  func loadSession() -> SessionInfo? {
    guard let data = try? Data(contentsOf: Self.sessionFileURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(SessionInfo.self, from: data)
  }

  /// Returns true if a new weekly session should start.
  ///
  /// Two conditions trigger a reset:
  /// - Today is the configured reset day and the current session started on a different day.
  /// - The session is more than 7 days old (handles missed reset days, e.g. the app was
  ///   not running when the reset day passed).
  ///
  /// Uses a fixed Gregorian calendar so weekday numbers are locale-independent.
  func shouldStartNewWeek(resetDay: Weekday) -> Bool {
    guard let session = loadSession() else { return true }
    let gregorian = Calendar(identifier: .gregorian)
    let today = Date()
    let weekday = gregorian.component(.weekday, from: today)

    if weekday == resetDay.rawValue && !gregorian.isDate(session.weekStartDate, inSameDayAs: today)
    {
      return true
    }

    if let daysSince = gregorian.dateComponents([.day], from: session.weekStartDate, to: today).day,
      daysSince >= 7
    {
      return true
    }

    return false
  }

  // MARK: - Run Tracking

  func lastRunDate() -> Date? {
    UserDefaults.standard.object(forKey: Self.lastRunKey) as? Date
  }

  func markRanToday() {
    UserDefaults.standard.set(Date(), forKey: Self.lastRunKey)
  }

  func hasRunToday() -> Bool {
    guard let lastRun = lastRunDate() else { return false }
    return Calendar.current.isDateInToday(lastRun)
  }

  // MARK: - Social Run Tracking

  func markSocialRan() {
    UserDefaults.standard.set(Date(), forKey: Self.lastSocialRunKey)
  }

  func hoursSinceLastSocialRun() -> Double {
    guard let lastRun = UserDefaults.standard.object(forKey: Self.lastSocialRunKey) as? Date
    else { return .infinity }
    return Date().timeIntervalSince(lastRun) / 3600
  }

  // MARK: - Seen Posts Dedup

  func loadSeenPostURLs() -> Set<String> {
    guard let data = try? Data(contentsOf: Self.seenPostsFileURL),
      let urls = try? JSONDecoder().decode(Set<String>.self, from: data)
    else { return [] }
    return urls
  }

  func saveSeenPostURLs(_ urls: Set<String>) {
    try? FileManager.default.createDirectory(
      at: Self.appSupportDirectoryURL, withIntermediateDirectories: true)
    guard let data = try? JSONEncoder().encode(urls) else { return }
    try? data.write(to: Self.seenPostsFileURL)
  }

  /// Add new URLs to seen set, pruning entries older than 7 days worth (cap at 500 to prevent unbounded growth).
  func markPostsSeen(_ newURLs: [String]) {
    var seen = loadSeenPostURLs()
    seen.formUnion(newURLs)
    // Cap at 500 most recent to prevent unbounded growth
    if seen.count > 500 {
      let sorted = Array(seen)
      seen = Set(sorted.suffix(500))
    }
    saveSeenPostURLs(seen)
  }
}
