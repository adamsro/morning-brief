import Foundation

struct ReportMetadata: Codable, Sendable {
  let date: Date
  let reportPath: String
  let generationDurationSeconds: Double
  let sessionId: String
}
