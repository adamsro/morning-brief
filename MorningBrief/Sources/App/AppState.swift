import Foundation

@MainActor
@Observable
final class AppState {
  var latestMetadata: ReportMetadata?
  var chatMessages: [ChatMessage] = []
  var status: Status = .idle
  var error: AppError?

  enum Status {
    case idle
    case generating
    case chatAvailable
  }

  private let claudeService = ClaudeService()

  func loadLatestReport() {
    guard let metadata = StorageService.shared.loadLatestMetadata(),
      let content = StorageService.shared.loadReportContent(at: metadata.reportPath)
    else { return }
    applyReport(metadata: metadata, markdown: content)
  }

  func handleReportGenerated(metadata: ReportMetadata, markdown: String) {
    applyReport(metadata: metadata, markdown: markdown)
    error = nil
  }

  private func applyReport(metadata: ReportMetadata, markdown: String) {
    latestMetadata = metadata
    chatMessages = [ChatMessage(role: .assistant, content: markdown, timestamp: metadata.date)]
    status = .chatAvailable
  }

  func sendFollowUp(_ question: String) {
    guard let sessionId = latestMetadata?.sessionId else {
      error = .generationFailed(detail: "No active session. Generate a brief first.")
      return
    }

    let userMessage = ChatMessage(role: .user, content: question)
    chatMessages.append(userMessage)

    let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
    chatMessages.append(assistantMessage)
    let assistantIndex = chatMessages.count - 1

    Task {
      let stream = await claudeService.sendFollowUp(
        sessionId: sessionId, question: question)
      do {
        for try await delta in stream {
          chatMessages[assistantIndex].content += delta
        }
        chatMessages[assistantIndex].isStreaming = false
      } catch {
        chatMessages[assistantIndex].isStreaming = false
        if chatMessages[assistantIndex].content.isEmpty {
          chatMessages[assistantIndex].content = "*Error: \(error.localizedDescription)*"
        }
        self.error = .generationFailed(detail: error.localizedDescription)
      }
    }
  }
}
