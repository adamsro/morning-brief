import Foundation
import OSLog

private let logger = Logger(subsystem: "com.morningbrief.app", category: "SocialMonitorService")

actor SocialMonitorService {
  static let shared = SocialMonitorService()

  struct SocialPost: Sendable {
    let source: String
    let title: String
    let snippet: String
    let url: String
    let subreddit: String?
    let score: Int
    let commentCount: Int
    let timestamp: Date
  }

  /// Returned by `fetchRecentPosts` so callers can surface fetch errors to the user.
  struct FetchResult: Sendable {
    let posts: [SocialPost]
    /// True if one or more network requests failed (e.g. 429 rate-limit).
    /// The brief will still be generated, but without full social context.
    let hadErrors: Bool
  }

  private static let userAgent = "MorningBrief/1.0 (competitive-intel-monitor)"

  // MARK: - Public

  func fetchRecentPosts(redditQueries: [String], hnQueries: [String]) async -> FetchResult {
    async let redditResult = fetchReddit(queries: redditQueries)
    async let hnResult = fetchHN(queries: hnQueries)

    let (redditPosts, redditHadErrors) = await redditResult
    let (hnPosts, hnHadErrors) = await hnResult

    let allPosts = redditPosts + hnPosts

    var seen = Set<String>()
    let unique = allPosts.filter { post in
      let key = post.url.lowercased()
      if seen.contains(key) { return false }
      seen.insert(key)
      return true
    }

    let sorted = unique.sorted { $0.timestamp > $1.timestamp }
    return FetchResult(posts: sorted, hadErrors: redditHadErrors || hnHadErrors)
  }

  // MARK: - Reddit

  private func fetchReddit(queries: [String]) async -> (posts: [SocialPost], hadErrors: Bool) {
    let urls: [URL] = queries.compactMap { query in
      guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      else { return nil }
      return URL(string: "https://www.reddit.com/search.json?q=\(encoded)&sort=new&t=day&limit=25")
    }

    var hadErrors = false
    let results = await withTaskGroup(of: (posts: [SocialPost], failed: Bool).self) { group in
      for url in urls {
        group.addTask { await self.fetchRedditURL(url) }
      }
      var combined: [SocialPost] = []
      for await batch in group {
        if batch.failed { hadErrors = true }
        combined += batch.posts
      }
      return combined
    }

    return (posts: deduplicatedByURL(results), hadErrors: hadErrors)
  }

  private func fetchRedditURL(_ url: URL) async -> (posts: [SocialPost], failed: Bool) {
    var request = URLRequest(url: url)
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 15

    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse
    else {
      return (posts: [], failed: true)
    }

    guard http.statusCode == 200 else {
      logger.warning("Reddit request failed with HTTP \(http.statusCode) for \(url)")
      return (posts: [], failed: true)
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let listingData = json["data"] as? [String: Any],
      let children = listingData["children"] as? [[String: Any]]
    else {
      return (posts: [], failed: true)
    }

    let posts = children.compactMap { child -> SocialPost? in
      guard let postData = child["data"] as? [String: Any],
        let title = postData["title"] as? String,
        let permalink = postData["permalink"] as? String,
        let subreddit = postData["subreddit"] as? String,
        let score = postData["score"] as? Int,
        let numComments = postData["num_comments"] as? Int,
        let createdUtc = postData["created_utc"] as? Double
      else { return nil }

      let selftext = (postData["selftext"] as? String) ?? ""

      return SocialPost(
        source: "reddit",
        title: title,
        snippet: String(selftext.prefix(200)),
        url: "https://www.reddit.com\(permalink)",
        subreddit: subreddit,
        score: score,
        commentCount: numComments,
        timestamp: Date(timeIntervalSince1970: createdUtc)
      )
    }
    return (posts: posts, failed: false)
  }

  // MARK: - Hacker News

  private func fetchHN(queries: [String]) async -> (posts: [SocialPost], hadErrors: Bool) {
    let oneDayAgo = Int(Date().timeIntervalSince1970) - 86400
    let urls: [URL] = queries.compactMap { query in
      guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      else { return nil }
      return URL(
        string:
          "https://hn.algolia.com/api/v1/search_by_date?query=\(encoded)&tags=story&numericFilters=created_at_i>\(oneDayAgo)&hitsPerPage=25"
      )
    }

    var hadErrors = false
    let results = await withTaskGroup(of: (posts: [SocialPost], failed: Bool).self) { group in
      for url in urls {
        group.addTask { await self.fetchHNURL(url) }
      }
      var combined: [SocialPost] = []
      for await batch in group {
        if batch.failed { hadErrors = true }
        combined += batch.posts
      }
      return combined
    }

    return (posts: deduplicatedByURL(results), hadErrors: hadErrors)
  }

  private func fetchHNURL(_ url: URL) async -> (posts: [SocialPost], failed: Bool) {
    var request = URLRequest(url: url)
    request.timeoutInterval = 15

    guard let (data, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse,
      http.statusCode == 200
    else {
      return (posts: [], failed: true)
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let hits = json["hits"] as? [[String: Any]]
    else {
      return (posts: [], failed: true)
    }

    let posts = hits.compactMap { hit -> SocialPost? in
      guard let title = hit["title"] as? String,
        let objectID = hit["objectID"] as? String,
        let points = hit["points"] as? Int,
        let numComments = hit["num_comments"] as? Int,
        let createdAtI = hit["created_at_i"] as? Int
      else { return nil }

      return SocialPost(
        source: "hn",
        title: title,
        snippet: "",
        url: "https://news.ycombinator.com/item?id=\(objectID)",
        subreddit: nil,
        score: points,
        commentCount: numComments,
        timestamp: Date(timeIntervalSince1970: Double(createdAtI))
      )
    }
    return (posts: posts, failed: false)
  }

  // MARK: - Helpers

  private func deduplicatedByURL(_ posts: [SocialPost]) -> [SocialPost] {
    var seen = Set<String>()
    var result: [SocialPost] = []
    for post in posts where !seen.contains(post.url) {
      seen.insert(post.url)
      result.append(post)
    }
    return result
  }
}
