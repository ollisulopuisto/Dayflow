import Foundation

/// Transfers screenshot batches to an always-on Dayflow queue service on the Studio.
/// Analysis remains on the Studio; this client sends only resized JPEG copies.
enum StudioBatchQueue {
  private static let endpointKey = "studioBatchQueueURL"
  private static let tokenKey = "studioBatchQueueToken"
  private static let deviceKey = "studioBatchQueueDeviceID"
  private static let maxImagesPerBatch = 15
  private static let backgroundQueue = DispatchQueue(
    label: "com.dayflow.studio-batch-upload", qos: .background)
  private static let inFlight = UploadState()

  private final class UploadState: @unchecked Sendable {
    private let lock = NSLock()
    private var uploadingBatchID: Int64?
    private var isPolling = false

    func beginUpload(batchID: Int64) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard uploadingBatchID == nil else { return false }
      uploadingBatchID = batchID
      return true
    }

    func finishUpload(batchID: Int64) {
      lock.lock()
      defer { lock.unlock() }
      guard uploadingBatchID == batchID else { return }
      uploadingBatchID = nil
    }

    func beginPolling() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard !isPolling else { return false }
      isPolling = true
      return true
    }

    func finishPolling() {
      lock.lock()
      defer { lock.unlock() }
      isPolling = false
    }
  }

  static var isEnabled: Bool {
    endpoint != nil
  }

  static func pollResults(store: any StorageManaging) {
    guard InputIdleSnapshot.isIdle(), let endpoint, inFlight.beginPolling() else { return }
    backgroundQueue.async {
      guard InputIdleSnapshot.isIdle() else {
        inFlight.finishPolling()
        return
      }
      importAvailableResults(from: endpoint, store: store) {
        inFlight.finishPolling()
      }
    }
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

  /// Queue the batch once and import any results the Studio has finished.
  static func submitAndImport(batchId: Int64, store: any StorageManaging) {
    guard InputIdleSnapshot.isIdle(), let endpoint, inFlight.beginUpload(batchID: batchId) else { return }
    backgroundQueue.async {
      guard InputIdleSnapshot.isIdle() else {
        inFlight.finishUpload(batchID: batchId)
        return
      }

      guard let batch = store.allBatches().first(where: { $0.id == batchId }) else {
        inFlight.finishUpload(batchID: batchId)
        return
      }

      guard batch.status != "studio_queued" && batch.status != "completed" else {
        inFlight.finishUpload(batchID: batchId)
        importAvailableResults(from: endpoint, store: store)
        return
      }

      guard let payload = makePayload(batchId: batchId, start: batch.start, end: batch.end, store: store),
        let body = try? JSONSerialization.data(withJSONObject: payload)
      else {
        inFlight.finishUpload(batchID: batchId)
        store.markBatchFailed(batchId: batchId, reason: "Could not prepare screenshots for Studio queue")
        return
      }

      // Image decoding and JSON construction can be expensive. If activity resumed while
      // preparing the payload, leave the batch pending for the next idle window.
      guard InputIdleSnapshot.isIdle() else {
        inFlight.finishUpload(batchID: batchId)
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
      let task = URLSession.shared.dataTask(with: request) { _, response, error in
        defer { inFlight.finishUpload(batchID: batchId) }
        guard error == nil, let response = response as? HTTPURLResponse,
          (200..<300).contains(response.statusCode)
        else {
          print("Studio queue upload failed for batch \(batchId): \(error?.localizedDescription ?? "HTTP error")")
          return
        }
        store.updateBatchStatus(batchId: batchId, status: "studio_queued")
        if InputIdleSnapshot.isIdle() {
          importAvailableResults(from: endpoint, store: store)
        }
      }
      task.priority = 0.1
      task.resume()
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
      autoreleasepool {
        guard let data = screenshot.jpegData(maxHeight: 720, quality: 0.85) else { return nil }
        return [
          "id": screenshot.id,
          "captured_at": screenshot.capturedAt,
          "idle_seconds": screenshot.idleSecondsAtCapture.map { $0 as Any } ?? NSNull(),
          "image_base64": data.base64EncodedString(),
        ]
      }
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

  private static func importAvailableResults(
    from endpoint: URL,
    store: any StorageManaging,
    completion: (() -> Void)? = nil
  ) {
    var request = URLRequest(url: endpoint.appendingPathComponent("v1/results").appending(queryItems: [
      URLQueryItem(name: "device_id", value: deviceID)
    ]))
    request.timeoutInterval = 60
    if let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
      defer { completion?() }
      guard InputIdleSnapshot.isIdle() else { return }
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
        guard cardResults.allSatisfy({ $0 }) else { continue }
        if cards.isEmpty { store.updateBatchStatus(batchId: batchID, status: "completed_empty") }
        acknowledge(jobID: jobID, deviceID: deviceID, endpoint: endpoint)
      }
    }
    task.priority = 0.1
    task.resume()
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
