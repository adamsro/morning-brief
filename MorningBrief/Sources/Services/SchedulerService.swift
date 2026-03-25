import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.morningbrief.app", category: "SchedulerService")

@MainActor
@Observable
final class SchedulerService {
  var isGenerating = false
  var generationProgress = ""

  var onGenerationStarted: (() -> Void)?
  var onReportGenerated: ((ReportMetadata, String) -> Void)?
  var onError: ((AppError) -> Void)?

  private let claudeService = ClaudeService()
  private let discordService = DiscordService()
  private var timer: Timer?
  private var lastFailureDate: Date?

  func start() {
    Task {
      try? await Task.sleep(for: .seconds(3))
      await checkAndRunIfDue()
      await checkSocialIfDue()
    }

    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.checkAndRunIfDue()
        await self?.checkSocialIfDue()
      }
    }
    if let timer {
      RunLoop.main.add(timer, forMode: .common)
    }

    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        await self?.checkAndRunIfDue()
        await self?.checkSocialIfDue()
      }
    }
  }

  // MARK: - Brief Schedule

  func checkAndRunIfDue() async {
    guard !isGenerating else { return }
    guard !StorageService.shared.hasRunToday() else { return }

    let gregorian = Calendar(identifier: .gregorian)
    let weekday = gregorian.component(.weekday, from: Date())
    if weekday == 1 || weekday == 7 { return }

    if let lastFailure = lastFailureDate,
      Date().timeIntervalSince(lastFailure) < 300
    {
      return
    }

    let hour = Calendar.current.component(.hour, from: Date())
    let config = ConfigService.shared.config
    guard hour >= config.scheduleHour else { return }

    await generateBrief()
  }

  func forceGenerate() async {
    guard !isGenerating else { return }
    lastFailureDate = nil
    await generateBrief()
  }

  // MARK: - Social Schedule (twice daily, independent of brief)

  private func checkSocialIfDue() async {
    let config = ConfigService.shared.config
    guard config.socialMonitoringEnabled else { return }
    guard !isGenerating else { return }

    // Run if 10+ hours since last social run (roughly twice daily)
    let hoursSince = StorageService.shared.hoursSinceLastSocialRun()
    guard hoursSince >= 10 else { return }

    await runSocialMonitoring()
  }

  func forceSocialMonitoring() async {
    await runSocialMonitoring()
  }

  private func runSocialMonitoring() async {
    let config = ConfigService.shared.config
    let storage = StorageService.shared

    let fetchResult = await SocialMonitorService.shared.fetchRecentPosts(
      redditQueries: config.redditSearchQueries,
      hnQueries: config.hnSearchQueries
    )

    guard !fetchResult.posts.isEmpty else {
      storage.markSocialRan()
      return
    }

    // Filter out already-seen posts
    let seenURLs = storage.loadSeenPostURLs()
    let newPosts = fetchResult.posts.filter { !seenURLs.contains($0.url) }

    guard !newPosts.isEmpty else {
      storage.markSocialRan()
      return
    }

    // Post new Reddit items to Discord
    let redditPosts = newPosts.filter { $0.source == "reddit" }
    let hnPosts = newPosts.filter { $0.source == "hn" }

    if !redditPosts.isEmpty,
      !config.discordRedditWebhookURL.trimmingCharacters(in: .whitespaces).isEmpty
    {
      await discordService.postSocialPosts(
        webhookURL: config.discordRedditWebhookURL, posts: redditPosts)
    }
    if !hnPosts.isEmpty,
      !config.discordHNWebhookURL.trimmingCharacters(in: .whitespaces).isEmpty
    {
      await discordService.postSocialPosts(
        webhookURL: config.discordHNWebhookURL, posts: hnPosts)
    }

    // Mark all as seen
    storage.markPostsSeen(newPosts.map(\.url))
    storage.markSocialRan()

    if fetchResult.hadErrors {
      logger.warning("Some social feed requests failed during monitoring pass.")
    }
  }

  // MARK: - Brief Generation

  private func generateBrief() async {
    isGenerating = true
    generationProgress = "Fetching social posts..."
    onGenerationStarted?()

    let startTime = Date()
    let config = ConfigService.shared.config

    // Fetch social posts for brief context (uses all posts, not just unseen)
    var socialPosts: [SocialMonitorService.SocialPost] = []
    if config.socialMonitoringEnabled {
      let fetchResult = await SocialMonitorService.shared.fetchRecentPosts(
        redditQueries: config.redditSearchQueries,
        hnQueries: config.hnSearchQueries
      )
      socialPosts = fetchResult.posts
      if fetchResult.hadErrors {
        logger.warning("Some social feed requests failed; brief may lack full social context.")
        generationProgress = "Generating brief (social feeds partially unavailable)..."
      }
    }

    let gregorian = Calendar(identifier: .gregorian)
    let weekday = gregorian.component(.weekday, from: Date())
    let isMonday = weekday == 2
    let userPrompt = ConfigService.shared.buildPrompt(
      socialPosts: socialPosts, isMonday: isMonday)
    let systemPrompt = ConfigService.shared.systemPrompt

    let storage = StorageService.shared
    let existingSession: SessionInfo? =
      storage.shouldStartNewWeek(resetDay: config.weeklyResetDay) ? nil : storage.loadSession()

    do {
      generationProgress = "Generating brief..."
      let result: ReportResult

      if let session = existingSession {
        do {
          result = try await claudeService.runClaude(
            systemPrompt: systemPrompt,
            prompt: userPrompt,
            sessionId: session.sessionId
          )
        } catch ClaudeError.timeout {
          throw ClaudeError.timeout
        } catch {
          generationProgress = "Retrying with fresh session..."
          result = try await claudeService.runClaude(
            systemPrompt: systemPrompt,
            prompt: userPrompt,
            sessionId: nil
          )
        }
      } else {
        result = try await claudeService.runClaude(
          systemPrompt: systemPrompt,
          prompt: userPrompt,
          sessionId: nil
        )
      }

      let duration = Date().timeIntervalSince(startTime)

      let metadata = try storage.saveReport(
        markdown: result.markdown,
        sessionId: result.sessionId,
        duration: duration
      )

      let updatedSession: SessionInfo
      if let existing = existingSession {
        updatedSession = SessionInfo(
          sessionId: result.sessionId,
          weekStartDate: existing.weekStartDate,
          dayCount: existing.dayCount + 1
        )
      } else {
        updatedSession = SessionInfo(
          sessionId: result.sessionId,
          weekStartDate: Date(),
          dayCount: 1
        )
      }
      do {
        try storage.saveSession(updatedSession)
      } catch {
        logger.warning("Failed to save session state: \(error)")
      }

      storage.markRanToday()
      lastFailureDate = nil
      onReportGenerated?(metadata, result.markdown)

      if config.hasDiscordWebhook {
        generationProgress = "Posting to Discord..."
        await discordService.postBrief(
          webhookURL: config.discordWebhookURL, markdown: result.markdown)
      }

      if config.notificationsEnabled {
        NotificationService.shared.postReportReady(date: Date())
      }
    } catch let error as ClaudeError {
      lastFailureDate = Date()
      let appError: AppError
      switch error {
      case .notInstalled:
        appError = .claudeNotInstalled
      case .processFailure(_, let stderr):
        appError = .generationFailed(detail: stderr)
      case .jsonParseFailure(let detail):
        appError = .generationFailed(detail: detail)
      case .timeout:
        appError = .generationFailed(detail: "Claude Code timed out after 10 minutes")
      }

      onError?(appError)
      if config.notificationsEnabled {
        NotificationService.shared.postError(appError.message)
      }
    } catch {
      lastFailureDate = Date()
      let appError = AppError.generationFailed(detail: error.localizedDescription)
      onError?(appError)
      if config.notificationsEnabled {
        NotificationService.shared.postError(appError.message)
      }
    }

    isGenerating = false
    generationProgress = ""
  }
}
