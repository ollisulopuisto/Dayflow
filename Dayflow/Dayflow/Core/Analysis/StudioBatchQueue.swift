import Foundation

/// Upload bookkeeping for Studio batches: one upload per batch at a time, and an
/// exponential wait after each failure so an unreachable Studio does not cost CPU every minute.
struct StudioUploadBackoff {
  static let delays: [TimeInterval] = [60, 120, 300, 900, 3600]

  private var inFlight: Set<Int64> = []
  private var failures: [Int64: Int] = [:]
  private var nextAttempt: [Int64: Date] = [:]

  func shouldAttempt(_ batchId: Int64, now: Date) -> Bool {
    if inFlight.contains(batchId) { return false }
    if let next = nextAttempt[batchId], now < next { return false }
    return true
  }

  /// Marks the batch as uploading if it may be attempted now.
  mutating func tryBegin(_ batchId: Int64, now: Date) -> Bool {
    guard shouldAttempt(batchId, now: now) else { return false }
    inFlight.insert(batchId)
    return true
  }

  mutating func finish(_ batchId: Int64, succeeded: Bool, now: Date) {
    inFlight.remove(batchId)
    guard !succeeded else {
      failures[batchId] = nil
      nextAttempt[batchId] = nil
      return
    }
    let count = (failures[batchId] ?? 0) + 1
    failures[batchId] = count
    nextAttempt[batchId] = now.addingTimeInterval(Self.delays[min(count, Self.delays.count) - 1])
  }
}

/// Thread-safe holder for the upload schedule shared by every caller.
final class StudioUploadScheduler: @unchecked Sendable {
  private let lock = NSLock()
  private var backoff = StudioUploadBackoff()

  func shouldAttempt(_ batchId: Int64) -> Bool {
    lock.withLock { backoff.shouldAttempt(batchId, now: Date()) }
  }

  func tryBegin(_ batchId: Int64) -> Bool {
    lock.withLock { backoff.tryBegin(batchId, now: Date()) }
  }

  func finish(_ batchId: Int64, succeeded: Bool) {
    lock.withLock { backoff.finish(batchId, succeeded: succeeded, now: Date()) }
  }
}

/// Transfers screenshot batches to an always-on Dayflow queue service on the Studio.
/// Analysis remains on the Studio; this client sends only resized JPEG copies.
enum StudioBatchQueue {
  private static let endpointKey = "studioBatchQueueURL"
  private static let tokenKey = "studioBatchQueueToken"
  private static let deviceKey = "studioBatchQueueDeviceID"
  private static let maxImagesPerBatch = 15

  static let scheduler = StudioUploadScheduler()

  static var isEnabled: Bool {
    endpoint != nil
  }

  /// False while the batch is uploading or waiting out a failure backoff.
  static func shouldAttempt(batchId: Int64) -> Bool {
    scheduler.shouldAttempt(batchId)
  }

  static func pollResults(store: any StorageManaging) {
    guard let endpoint else { return }
    importAvailableResults(from: endpoint, store: store)
  }

  private static var endpoint: URL? {
    guard let raw = UserDefaults.standard.string(forKey: endpointKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty, let url = URL(string: raw), url.scheme == "http" || url.scheme == "https"
    else { return nil }
    return url
  }

  private static var deviceID: String {
    if let existing = UserDefaults.standard.string(forKey: deviceKey) { return existing }
    let value = UUID().uuidString.lowercased()
    UserDefaults.standard.set(value, forKey: deviceKey)
    return value
  }

  /// Queue the batch once. Results are imported by the per-minute poll, not per upload.
  static func submitAndImport(batchId: Int64, store: any StorageManaging) {
    guard endpoint != nil, scheduler.shouldAttempt(batchId) else { return }
    let batch = store.batch(id: batchId)
    guard let batch, let endpoint else { return }
    if batch.status != "studio_queued" && batch.status != "completed" {
      guard scheduler.tryBegin(batchId) else { return }
      guard let payload = makePayload(batchId: batchId, start: batch.start, end: batch.end, store: store),
        let body = try? JSONSerialization.data(withJSONObject: payload)
      else {
        store.markBatchFailed(batchId: batchId, reason: "Could not prepare screenshots for Studio queue")
        scheduler.finish(batchId, succeeded: true)
        return
      }
      var request = URLRequest(url: endpoint.appendingPathComponent("v1/jobs"))
      request.httpMethod = "POST"
      request.timeoutInterval = 180
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(deviceID, forHTTPHeaderField: "X-Dayflow-Device")
      if let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      }
      request.httpBody = body
      URLSession.shared.dataTask(with: request) { _, response, error in
        guard error == nil, let response = response as? HTTPURLResponse,
          (200..<300).contains(response.statusCode)
        else {
          print("Studio queue upload failed for batch \(batchId): \(error?.localizedDescription ?? "HTTP error")")
          scheduler.finish(batchId, succeeded: false)
          return
        }
        store.updateBatchStatus(batchId: batchId, status: "studio_queued")
        scheduler.finish(batchId, succeeded: true)
      }.resume()
    }
  }

  private static func makePayload(batchId: Int64, start: Int, end: Int, store: any StorageManaging) -> [String: Any]? {
    let screenshots = store.screenshotsForBatch(batchId).sorted { $0.capturedAt < $1.capturedAt }
    guard !screenshots.isEmpty else { return nil }
    let sampled: [Screenshot]
    if screenshots.count <= maxImagesPerBatch {
      sampled = screenshots
    } else {
      sampled = (0..<maxImagesPerBatch).map { index in
        screenshots[index * (screenshots.count - 1) / (maxImagesPerBatch - 1)]
      }
    }
    let encoded = sampled.compactMap { screenshot -> [String: Any]? in
      guard let data = screenshot.jpegData(maxHeight: 720, quality: 0.85) else { return nil }
      return [
        "id": screenshot.id,
        "captured_at": screenshot.capturedAt,
        "idle_seconds": screenshot.idleSecondsAtCapture.map { $0 as Any } ?? NSNull(),
        "image_base64": data.base64EncodedString(),
      ]
    }
    guard !encoded.isEmpty else { return nil }
    let categories = (try? JSONEncoder().encode(CategoryStore.descriptorsForLLM()))
      .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]] ?? []
    return [
      "job_id": "\(deviceID)-\(batchId)",
      "device_id": deviceID,
      "batch_id": batchId,
      "start_ts": start,
      "end_ts": end,
      "timezone": TimeZone.current.identifier,
      "schedule_timezone": "Europe/Helsinki",
      "window_start": UserDefaults.standard.string(forKey: "studioBatchWindowStart") ?? "07:00",
      "window_end": UserDefaults.standard.string(forKey: "studioBatchWindowEnd") ?? "01:00",
      "categories": categories,
      "screenshots": encoded,
    ]
  }

  private static func importAvailableResults(from endpoint: URL, store: any StorageManaging) {
    var request = URLRequest(url: endpoint.appendingPathComponent("v1/results").appending(queryItems: [
      URLQueryItem(name: "device_id", value: deviceID)
    ]))
    request.timeoutInterval = 60
    if let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    URLSession.shared.dataTask(with: request) { data, response, error in
      guard error == nil, let response = response as? HTTPURLResponse,
        (200..<300).contains(response.statusCode), let data,
        let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
      else { return }
      for result in results {
        guard let jobID = result["job_id"] as? String,
          let batchIDNumber = result["batch_id"] as? NSNumber,
          let cards = result["cards"] as? [[String: Any]] else { continue }
        let batchID = batchIDNumber.int64Value
        var importedSignatures = Set(store.fetchTimelineCards(forBatch: batchID).map {
          "\($0.startTimestamp)|\($0.endTimestamp)|\($0.title)"
        })
        let cardResults = cards.map { card -> Bool in
          guard let startTime = card["start_time"] as? String,
            let endTime = card["end_time"] as? String,
            let category = card["category"] as? String,
            let subcategory = card["subcategory"] as? String,
            let title = card["title"] as? String,
            let summary = card["summary"] as? String,
            let detail = card["detailed_summary"] as? String else { return false }
          let signature = "\(startTime)|\(endTime)|\(title)"
          if importedSignatures.contains(signature) { return true }
          let shell = TimelineCardShell(
            startTimestamp: startTime, endTimestamp: endTime, category: category,
            subcategory: subcategory, title: title, summary: summary,
            detailedSummary: detail, distractions: nil, appSites: nil,
            isBackupGenerated: nil, idleMetadata: nil)
          guard store.saveTimelineCardShell(batchId: batchID, card: shell) != nil else { return false }
          importedSignatures.insert(signature)
          return true
        }
        guard cardResults.allSatisfy({ $0 }) else {
          print("Studio import incomplete for batch \(batchID): \(cardResults.filter { !$0 }.count) of \(cardResults.count) cards not saved")
          continue
        }
        store.updateBatchStatus(
          batchId: batchID,
          status: cards.isEmpty ? "completed_empty" : "analyzed"
        )
        acknowledge(jobID: jobID, deviceID: deviceID, endpoint: endpoint)
      }
    }.resume()
  }

  private static func acknowledge(jobID: String, deviceID: String, endpoint: URL) {
    var request = URLRequest(url: endpoint.appendingPathComponent("v1/ack"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["job_id": jobID, "device_id": deviceID])
    URLSession.shared.dataTask(with: request).resume()
  }
}
