import SwiftUI

struct ChatView: View {
  @Environment(AppState.self) private var appState
  @State private var inputText = ""

  private var isStreaming: Bool {
    appState.chatMessages.last?.isStreaming == true
  }

  private var lastMessageContent: String {
    appState.chatMessages.last?.content ?? ""
  }

  var body: some View {
    VStack(spacing: 0) {
      if let error = appState.error {
        ErrorBanner(error: error) {
          appState.error = nil
        }
      }

      if appState.chatMessages.isEmpty {
        emptyState
      } else {
        messageList
      }

      Divider()

      InputBar(
        text: $inputText,
        isDisabled: isStreaming || appState.status != .chatAvailable
      ) {
        let question = inputText
        appState.sendFollowUp(question)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .frame(minWidth: 600, minHeight: 400)
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Spacer()
      Image(systemName: "newspaper")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
      Text("No report yet")
        .font(.title2)
        .foregroundStyle(.secondary)
      Text("Generate a brief from the menu bar to get started.")
        .font(.callout)
        .foregroundStyle(.tertiary)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(appState.chatMessages) { message in
            MessageBubble(message: message)
              .id(message.id)
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: appState.chatMessages.count) {
        scrollToBottom(proxy)
      }
      .onChange(of: lastMessageContent) {
        if isStreaming {
          scrollToBottom(proxy)
        }
      }
    }
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy) {
    if let last = appState.chatMessages.last {
      withAnimation(.easeOut(duration: 0.15)) {
        proxy.scrollTo(last.id, anchor: .bottom)
      }
    }
  }
}
