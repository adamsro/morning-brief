import SwiftUI

struct MessageBubble: View {
  let message: ChatMessage

  var body: some View {
    HStack(alignment: .top) {
      if message.role == .user { Spacer(minLength: 60) }

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
        if message.role == .assistant {
          MarkdownContentView(markdown: message.content)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Text(message.content)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        if message.isStreaming {
          HStack(spacing: 4) {
            ProgressView()
              .controlSize(.small)
            Text("Thinking...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      if message.role == .assistant { Spacer(minLength: 0) }
    }
  }
}
