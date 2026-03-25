import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  let appState = AppState()
  let schedulerService = SchedulerService()

  private var statusBarItem: NSStatusItem!
  private var chatWindowController: NSWindowController?
  private var settingsWindowController: NSWindowController?
  private var statusAnimationTimer: Timer?

  private static let menuDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    ConfigService.shared.load()
    appState.loadLatestReport()
    setupMenuBar()

    NotificationService.shared.setup()
    Task { await NotificationService.shared.requestPermission() }

    // UNUserNotificationCenterDelegate callbacks are nonisolated and cannot reach
    // @MainActor methods directly — NotificationCenter bridges the isolation boundary.
    NotificationCenter.default.addObserver(
      forName: .openChatWindow,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.openChatWindow()
      }
    }

    // Wire SchedulerService events with direct closures — both are @MainActor, no indirection needed.
    schedulerService.onGenerationStarted = { [weak self] in
      self?.startStatusAnimation()
    }
    schedulerService.onReportGenerated = { [weak self] metadata, markdown in
      self?.appState.handleReportGenerated(metadata: metadata, markdown: markdown)
      self?.stopStatusAnimation()
    }
    schedulerService.onError = { [weak self] error in
      self?.appState.error = error
      self?.stopStatusAnimation()
    }

    schedulerService.start()
  }

  // MARK: - Menu Bar

  private func setupMenuBar() {
    statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusBarItem.button {
      button.image = NSImage(
        systemSymbolName: "newspaper",
        accessibilityDescription: "Morning Brief"
      )
    }
    let menu = NSMenu()
    menu.delegate = self
    statusBarItem.menu = menu
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    buildMenu(menu)
  }

  private func buildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    let statusText: String
    if schedulerService.isGenerating {
      statusText =
        schedulerService.generationProgress.isEmpty
        ? "Generating report..."
        : schedulerService.generationProgress
    } else if let metadata = appState.latestMetadata {
      let dateStr = Self.menuDateFormatter.string(from: metadata.date)
      let duration = Int(metadata.generationDurationSeconds)
      statusText = "Last report: \(dateStr) (\(duration)s)"
    } else if StorageService.shared.hasRunToday() {
      statusText = "Report generated today"
    } else {
      let config = ConfigService.shared.config
      statusText = "Next report at \(BriefConfig.formattedHour(config.scheduleHour))"
    }

    let statusMenuItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
    statusMenuItem.isEnabled = false
    let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    statusMenuItem.attributedTitle = NSAttributedString(
      string: statusText,
      attributes: [
        .font: font,
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
    )
    menu.addItem(statusMenuItem)

    if let error = appState.error {
      let errorItem = NSMenuItem(title: error.message, action: nil, keyEquivalent: "")
      errorItem.isEnabled = false
      errorItem.attributedTitle = NSAttributedString(
        string: error.message,
        attributes: [
          .font: NSFont.systemFont(ofSize: 11),
          .foregroundColor: NSColor.systemOrange,
        ]
      )
      menu.addItem(errorItem)
    }

    menu.addItem(.separator())

    let genItem = NSMenuItem(
      title: "Generate Report",
      action: schedulerService.isGenerating ? nil : #selector(generateReport),
      keyEquivalent: "g"
    )
    genItem.keyEquivalentModifierMask = .command
    genItem.isEnabled = !schedulerService.isGenerating
    genItem.target = self
    menu.addItem(genItem)

    if appState.latestMetadata != nil {
      let openItem = NSMenuItem(
        title: "Open Latest Report",
        action: #selector(openLatestReport),
        keyEquivalent: "o"
      )
      openItem.keyEquivalentModifierMask = .command
      openItem.target = self
      menu.addItem(openItem)
    }

    menu.addItem(.separator())

    let settingsItem = NSMenuItem(
      title: "Settings...",
      action: #selector(openSettings),
      keyEquivalent: ","
    )
    settingsItem.keyEquivalentModifierMask = .command
    settingsItem.target = self
    menu.addItem(settingsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit Morning Brief",
      action: #selector(quit),
      keyEquivalent: "q"
    )
    quitItem.keyEquivalentModifierMask = .command
    quitItem.target = self
    menu.addItem(quitItem)
  }

  // MARK: - Status Icon Animation

  private var animationFrame = 0

  private func startStatusAnimation() {
    statusAnimationTimer?.invalidate()
    animationFrame = 0
    statusAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        guard let self, let button = self.statusBarItem.button else { return }
        let symbols = ["newspaper", "newspaper.fill", "arrow.clockwise", "newspaper.fill"]
        button.image = NSImage(
          systemSymbolName: symbols[self.animationFrame % symbols.count],
          accessibilityDescription: "Generating report"
        )
        self.animationFrame += 1
      }
    }
  }

  private func stopStatusAnimation() {
    statusAnimationTimer?.invalidate()
    statusAnimationTimer = nil
    statusBarItem.button?.image = NSImage(
      systemSymbolName: "newspaper",
      accessibilityDescription: "Morning Brief"
    )
  }

  // MARK: - Actions

  @objc private func generateReport() {
    Task {
      await schedulerService.forceGenerate()
    }
  }

  @objc private func openLatestReport() {
    openChatWindow()
  }

  @objc private func openSettings() {
    if let wc = settingsWindowController, let window = wc.window, window.isVisible {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Morning Brief Settings"
    window.center()
    window.contentView = NSHostingView(rootView: SettingsView().environment(appState))
    let wc = NSWindowController(window: window)
    wc.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    settingsWindowController = wc
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  func openChatWindow() {
    if let wc = chatWindowController, let window = wc.window, window.isVisible {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    if appState.chatMessages.isEmpty {
      appState.loadLatestReport()
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Morning Brief"
    window.center()
    window.contentView = NSHostingView(rootView: ChatView().environment(appState))
    window.setFrameAutosaveName("MorningBriefChat")

    let wc = NSWindowController(window: window)
    wc.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    chatWindowController = wc
  }

}
