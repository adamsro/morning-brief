import SwiftUI

@main
struct MorningBriefApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    // Pure menu bar app. Settings scene doesn't create a visible window on launch.
    // All windows are managed imperatively by AppDelegate.
    Settings {
      EmptyView()
    }
  }
}
