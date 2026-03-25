import Foundation
import OSLog

private let logger = Logger(subsystem: "com.morningbrief.app", category: "ClaudeService")

enum ClaudeError: LocalizedError, Sendable {
  case notInstalled
  case processFailure(exitCode: Int32, stderr: String)
  case jsonParseFailure(String)
  case timeout

  var errorDescription: String? {
    switch self {
    case .notInstalled:
      return "Claude Code CLI not found"
    case .processFailure(let code, let stderr):
      return "Process exited with code \(code): \(stderr)"
    case .jsonParseFailure(let detail):
      return "Failed to parse Claude response: \(detail)"
    case .timeout:
      return "Claude Code timed out"
    }
  }
}

struct ReportResult: Sendable {
  let markdown: String
  let sessionId: String
}

actor ClaudeService {

  func findClaudeBinary() -> URL? {
    // Use the login shell's PATH to find claude — macOS strips PATH for GUI apps,
    // so npm/nvm/homebrew paths are invisible to ProcessInfo.environment["PATH"].
    if let shellPath = resolveViaLoginShell() {
      return shellPath
    }

    // Fallback: check well-known locations directly
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let candidates = [
      "\(home)/.local/bin/claude",
      "\(home)/.npm-global/bin/claude",
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude",
    ]

    for path in candidates {
      if FileManager.default.isExecutableFile(atPath: path) {
        return URL(fileURLWithPath: path)
      }
    }

    // Last resort: check the process environment PATH (works when launched from terminal)
    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
      for dir in pathEnv.split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("claude")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
          return candidate
        }
      }
    }

    return nil
  }

  private func resolveViaLoginShell() -> URL? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-l", "-c", "which claude"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard
      let path = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !path.isEmpty,
      FileManager.default.isExecutableFile(atPath: path)
    else { return nil }

    return URL(fileURLWithPath: path)
  }

  // MARK: - Follow-up Chat (streaming)

  func sendFollowUp(
    sessionId: String, question: String
  ) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          guard let binary = self.findClaudeBinary() else {
            continuation.finish(throwing: ClaudeError.notInstalled)
            return
          }

          let process = Process()
          process.executableURL = binary
          process.arguments = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--resume", sessionId,
          ]

          let stdinPipe = Pipe()
          let stdoutPipe = Pipe()
          let stderrPipe = Pipe()
          process.standardInput = stdinPipe
          process.standardOutput = stdoutPipe
          process.standardError = stderrPipe

          try process.run()

          stdinPipe.fileHandleForWriting.write(Data(question.utf8))
          stdinPipe.fileHandleForWriting.closeFile()

          // Build a non-blocking AsyncStream from the readabilityHandler so the
          // 5-minute timeout check is always reachable — availableData blocks the
          // thread indefinitely when the process is alive but silent (e.g. mid-search).
          let (chunkStream, chunkContinuation) = AsyncStream<Data>.makeStream()
          stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
              // EOF — process has closed its stdout end
              handle.readabilityHandler = nil
              chunkContinuation.finish()
            } else {
              chunkContinuation.yield(data)
            }
          }

          // Terminate the subprocess if the surrounding Task is cancelled.
          await withTaskCancellationHandler {
            // 5-minute timeout for follow-up streaming
            let streamDeadline = Date().addingTimeInterval(300)
            var buffer = Data()

            for await chunk in chunkStream {
              if Date() > streamDeadline {
                process.terminate()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: ClaudeError.timeout)
                return
              }

              buffer.append(chunk)

              while let newlineRange = buffer.range(of: Data("\n".utf8)) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard let line = String(data: lineData, encoding: .utf8),
                  !line.trimmingCharacters(in: .whitespaces).isEmpty
                else { continue }

                if let delta = Self.parseStreamDelta(line) {
                  continuation.yield(delta)
                }
              }
            }

            process.waitUntilExit()
            continuation.finish()
          } onCancel: {
            process.terminate()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            chunkContinuation.finish()
          }
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  // MARK: - Report Generation

  func runClaude(
    systemPrompt: String, prompt: String, sessionId: String?
  ) async throws -> ReportResult {
    guard let binary = findClaudeBinary() else {
      logger.error("Claude binary not found")
      throw ClaudeError.notInstalled
    }

    logger.info("Using Claude binary at \(binary.path)")

    let process = Process()
    process.executableURL = binary

    var args = [
      "-p",
      "--output-format", "stream-json",
      "--verbose",
      "--allowedTools", "WebSearch,WebFetch",
      "--system-prompt", systemPrompt,
    ]
    if let sessionId {
      args += ["--resume", sessionId]
      logger.info("Resuming session \(sessionId)")
    } else {
      logger.info("Starting fresh session")
    }
    process.arguments = args

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    logger.info("Claude process launched (pid \(process.processIdentifier))")

    stdinPipe.fileHandleForWriting.write(Data(prompt.utf8))
    stdinPipe.fileHandleForWriting.closeFile()
    logger.info("Prompt written to stdin (\(prompt.utf8.count) bytes)")

    // Drain stdout and stderr on background threads concurrently with the
    // timeout loop. If we wait until the process exits before calling
    // readDataToEndOfFile(), the pipe's kernel buffer (~64 KB on macOS) can
    // fill, causing the subprocess to block on write(2) — deadlock. Reading
    // off-thread keeps the buffer clear so the process always makes progress.
    async let stdoutData: Data = withCheckedThrowingContinuation { cont in
      DispatchQueue.global(qos: .utility).async {
        cont.resume(returning: stdoutPipe.fileHandleForReading.readDataToEndOfFile())
      }
    }
    async let stderrData: Data = withCheckedThrowingContinuation { cont in
      DispatchQueue.global(qos: .utility).async {
        cont.resume(returning: stderrPipe.fileHandleForReading.readDataToEndOfFile())
      }
    }

    // Poll for exit with a 10-minute timeout. The drain tasks above ensure the
    // process is never blocked on a full pipe buffer while we wait.
    let deadline = Date().addingTimeInterval(600)
    while process.isRunning {
      if Date() > deadline {
        process.terminate()
        logger.error("Claude process timed out after 10 minutes")
        throw ClaudeError.timeout
      }
      try await Task.sleep(for: .milliseconds(500))
    }

    let stdout = try await stdoutData
    let stderr = try await stderrData

    let stderrString = String(data: stderr, encoding: .utf8) ?? ""
    logger.info("Claude process exited with code \(process.terminationStatus), stdout=\(stdout.count) bytes, stderr=\(stderr.count) bytes")
    if !stderrString.isEmpty {
      logger.warning("Claude stderr: \(stderrString.prefix(500))")
    }

    guard process.terminationStatus == 0 else {
      logger.error("Claude process failed: exit \(process.terminationStatus), stderr: \(stderrString.prefix(500))")
      throw ClaudeError.processFailure(exitCode: process.terminationStatus, stderr: stderrString)
    }

    // Parse stream-json: each line is a JSON object. Aggregate text from
    // assistant messages and extract session_id from the result line.
    let raw = String(data: stdout, encoding: .utf8) ?? ""
    let lines = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    logger.info("Stream output: \(lines.count) JSON lines")

    var aggregatedText = ""
    var returnedSessionId: String?

    for line in lines {
      guard let lineData = line.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
        let type = json["type"] as? String
      else { continue }

      switch type {
      case "assistant":
        // Extract text blocks from assistant message content
        if let message = json["message"] as? [String: Any],
          let content = message["content"] as? [[String: Any]]
        {
          for block in content {
            if let blockType = block["type"] as? String, blockType == "text",
              let text = block["text"] as? String
            {
              aggregatedText += text
            }
          }
        }
        if let sid = json["session_id"] as? String {
          returnedSessionId = sid
        }
      case "result":
        if let sid = json["session_id"] as? String {
          returnedSessionId = sid
        }
        // Also check the result field in case the CLI bug is fixed
        if aggregatedText.isEmpty, let result = json["result"] as? String, !result.isEmpty {
          aggregatedText = result
        }
      default:
        break
      }
    }

    guard let sessionId = returnedSessionId else {
      logger.error("No session_id found in stream output")
      throw ClaudeError.jsonParseFailure("Missing session_id in stream response")
    }

    if aggregatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      logger.error("Claude returned no text content. Session: \(sessionId). Lines: \(lines.count)")
      throw ClaudeError.jsonParseFailure("Claude returned an empty result — report would be blank")
    }

    logger.info("Report generated successfully: \(aggregatedText.count) chars, session \(sessionId)")
    return ReportResult(markdown: aggregatedText, sessionId: sessionId)
  }

  private static func parseStreamDelta(_ line: String) -> String? {
    guard let data = line.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    if let type = json["type"] as? String, type == "content_block_delta",
      let delta = json["delta"] as? [String: Any],
      let deltaType = delta["type"] as? String, deltaType == "text_delta",
      let text = delta["text"] as? String
    {
      return text
    }

    return nil
  }
}
