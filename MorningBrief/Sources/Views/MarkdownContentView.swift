import SwiftUI
import Textual

struct MarkdownContentView: View {
  let markdown: String

  var body: some View {
    StructuredText(markdown: markdown)
      .font(.system(size: 13))
      .foregroundStyle(Color(nsColor: .textColor))
      .textSelection(.enabled)
  }
}
