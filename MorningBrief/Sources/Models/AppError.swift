import Foundation

enum AppError: Equatable {
  case claudeNotInstalled
  case generationFailed(detail: String)

  var message: String {
    switch self {
    case .claudeNotInstalled:
      return
        "Claude Code is not installed. Install it from https://docs.anthropic.com/en/docs/claude-code"
    case .generationFailed(let detail):
      return "Brief generation failed: \(detail)"
    }
  }
}
