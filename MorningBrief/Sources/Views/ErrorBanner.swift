import SwiftUI

struct ErrorBanner: View {
  let error: AppError
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)

      Text(error.message)
        .font(.callout)
        .lineLimit(2)

      Spacer()

      Button("Dismiss") {
        onDismiss()
      }
      .buttonStyle(.plain)
      .font(.callout.weight(.medium))
    }
    .padding(10)
    .background(Color.orange.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .padding(.horizontal, 12)
    .padding(.top, 8)
  }
}
