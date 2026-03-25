import SwiftUI

struct InputBar: View {
  @Binding var text: String
  let isDisabled: Bool
  let onSend: () -> Void

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField("Ask a follow-up question...", text: $text, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(1...5)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onSubmit {
          if NSEvent.modifierFlags.contains(.command) {
            send()
          }
        }
        .disabled(isDisabled)

      Button(action: send) {
        Image(systemName: "arrow.up.circle.fill")
          .font(.title2)
      }
      .buttonStyle(.plain)
      .disabled(isDisabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .keyboardShortcut(.return, modifiers: .command)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func send() {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    text = ""
    onSend()
  }
}
