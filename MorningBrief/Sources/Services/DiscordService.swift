import Foundation
import os

actor DiscordService {
  private static let logger = Logger(
    subsystem: "com.morningbrief.app", category: "discord")
  private static let maxMessageLength = 2000

  func postSocialPosts(
    webhookURL: String, posts: [SocialMonitorService.SocialPost]
  ) async {
    guard let url = URL(string: webhookURL), !posts.isEmpty else { return }

    for post in posts {
      let sourceLabel: String
      if post.source == "reddit", let sub = post.subreddit {
        sourceLabel = "r/\(sub)"
      } else {
        sourceLabel = post.source.uppercased()
      }

      var message = "**[\(sourceLabel)]** \(post.title)\n"
      message += "Score: \(post.score) · \(post.commentCount) comments\n"
      message += post.url
      if !post.snippet.isEmpty {
        let truncated = String(post.snippet.prefix(300))
        message += "\n> \(truncated)"
      }

      let success = await postMessage(
        url: url, content: String(message.prefix(Self.maxMessageLength)))
      if !success {
        Self.logger.warning("Failed to post social item to Discord")
      }
      try? await Task.sleep(for: .milliseconds(300))
    }
  }

  func postBrief(webhookURL: String, markdown: String) async {
    guard let url = URL(string: webhookURL) else {
      Self.logger.warning("Invalid Discord webhook URL")
      return
    }

    let chunks = Self.splitIntoChunks(markdown)

    for (index, chunk) in chunks.enumerated() {
      let success = await postMessage(url: url, content: chunk)
      if !success {
        Self.logger.warning("Failed to post chunk \(index + 1)/\(chunks.count) to Discord")
        return
      }
      // Brief pause between messages to maintain ordering
      if index < chunks.count - 1 {
        try? await Task.sleep(for: .milliseconds(500))
      }
    }
  }

  private func postMessage(url: URL, content: String) async -> Bool {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 15

    let body: [String: String] = ["content": content]
    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
      return false
    }
    request.httpBody = bodyData

    guard let (_, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse,
      (200...299).contains(http.statusCode)
    else {
      return false
    }

    return true
  }

  static func splitIntoChunks(_ markdown: String) -> [String] {
    // Split on ## headers to keep sections together
    let sections = markdown.components(separatedBy: "\n## ")
    var chunks: [String] = []
    var current = ""

    for (index, section) in sections.enumerated() {
      let piece = index == 0 ? section : "## " + section

      if current.isEmpty {
        current = piece
      } else if (current + "\n\n" + piece).count <= maxMessageLength {
        current += "\n\n" + piece
      } else {
        // Flush current chunk
        if !current.isEmpty {
          chunks.append(contentsOf: splitLongSection(current))
        }
        current = piece
      }
    }

    if !current.isEmpty {
      chunks.append(contentsOf: splitLongSection(current))
    }

    return chunks
  }

  /// Split a single section that exceeds the message limit at paragraph boundaries.
  private static func splitLongSection(_ text: String) -> [String] {
    guard text.count > maxMessageLength else { return [text] }

    var chunks: [String] = []
    var current = ""

    for paragraph in text.components(separatedBy: "\n\n") {
      if current.isEmpty {
        current = paragraph
      } else if (current + "\n\n" + paragraph).count <= maxMessageLength {
        current += "\n\n" + paragraph
      } else {
        if !current.isEmpty { chunks.append(current) }
        // If a single paragraph exceeds the limit, hard-split it
        if paragraph.count > maxMessageLength {
          var remaining = paragraph
          while !remaining.isEmpty {
            let prefix = String(remaining.prefix(maxMessageLength))
            chunks.append(prefix)
            remaining = String(remaining.dropFirst(prefix.count))
          }
          current = ""
        } else {
          current = paragraph
        }
      }
    }

    if !current.isEmpty { chunks.append(current) }
    return chunks
  }
}
