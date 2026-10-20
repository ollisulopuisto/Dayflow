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
    private var uploadFailureCount = 0
    private var nextUploadAttempt = Date.distantPast
    private var pollBackoffCount = 0
    private var nextPollAttempt = Date.distantPast

    func beginUpload(batchID: Int64) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard uploadingBatchID == nil, Date() >= nextUploadAttempt else { return false }
      uploadingBatchID = batchID
      return true
    }

    func finishUpload(batchID: Int64, failed: Bool = false) {
      lock.lock()
      defer { lock.unlock() }
      guard uploadingBatchID == batchID else { return }
      uploadingBatchID = nil
      if failed {
        uploadFailureCount += 1
        nextUploadAttempt = Date().addingTimeInterval(
          Self.backoffDelay(attempt: uploadFailureCount, cap: 15 * 60))
      } else {
        uploadFailureCount = 0
        nextUploadAttempt = .distantPast
      }
    }

    func beginPolling() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard !isPolling, Date() >= nextPollAttempt else { return false }
      isPolling = true
      return true
    }

    func finishPolling(resultCount: Int? = nil, failed: Bool = false) {
      lock.lock()
      defer { lock.unlock() }
      isPolling = false
      guard failed || resultCount != nil else { return }
      if failed || resultCount == 0 {
        pollBackoffCount += 1
        nextPollAttempt = Date().addingTimeInterval(
          Self.backoffDelay(attempt: pollBackoffCount, cap: 5 * 60))
      } else {
        pollBackoffCount = 0
        nextPollAttempt = Date().addingTimeInterval(60)
      }
    }

    private static func backoffDelay(attempt: Int, cap: TimeInterval) -> TimeInterval {
      min(cap, 60.0 * pow(2.0, Double(max(0, attempt - 1))))
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
        inFlight.finishPolling(resultCount: $0, failed: $1)
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
        pollResults(store: store)
        return
      }

      guard let bodyFile = makeUploadFile(
        batchId: batchId, start: batch.start, end: batch.end, store: store)
      else {
        inFlight.finishUpload(batchID: batchId)
        store.markBatchFailed(batchId: batchId, reason: "Could not prepare screenshots for Studio queue")
        return
      }

      // Image decoding and JSON construction can be expensive. If activity resumed while
      // preparing the payload, leave the batch pending for the next idle window.
      guard InputIdleSnapshot.isIdle() else {
        try? FileManager.default.removeItem(at: bodyFile)
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
      let task = URLSession.shared.uploadTask(with: request, fromFile: bodyFile) { _, response, error in
        try? FileManager.default.removeItem(at: bodyFile)
        guard error == nil, let response = response as? HTTPURLResponse,
          (200..<300).contains(response.statusCode)
        else {
          inFlight.finishUpload(batchID: batchId, failed: true)
          print("Studio queue upload failed for batch \(batchId): \(error?.localizedDescription ?? "HTTP error")")
          return
        }
        inFlight.finishUpload(batchID: batchId)
        store.updateBatchStatus(batchId: batchId, status: "studio_queued")
        if InputIdleSnapshot.isIdle() {
          pollResults(store: store)
        }
      }
      task.priority = 0.1
      task.resume()
    }
  }

  private static func makeUploadFile(
    batchId: Int64, start: Int, end: Int, store: any StorageManaging
  ) -> URL? {
    removeStaleUploadFiles()
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
    let categories = (try? JSONEncoder().encode(CategoryStore.descriptorsForLLM()))
      .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]] ?? []
    let metadata: [String: Any] = [
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
    ]

    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayflow-studio-upload-\(UUID().uuidString).json")
    guard FileManager.default.createFile(atPath: fileURL.path, contents: nil),
      let metadataData = try? JSONSerialization.data(withJSONObject: metadata),
      metadataData.last == 125
    else {
      try? FileManager.default.removeItem(at: fileURL)
      return nil
    }

    do {
      let file = try FileHandle(forWritingTo: fileURL)
      do {
        try file.write(contentsOf: Data(metadataData.dropLast()))
        try file.write(contentsOf: Data(",\"screenshots\":[".utf8))

        var hasWrittenScreenshot = false
        for screenshot in sampled {
          let screenshotData = autoreleasepool { () -> Data? in
            guard let imageData = screenshot.jpegData(maxHeight: 720, quality: 0.85) else {
              return nil
            }
            let screenshotObject: [String: Any] = [
              "id": screenshot.id,
              "captured_at": screenshot.capturedAt,
              "idle_seconds": screenshot.idleSecondsAtCapture.map { $0 as Any } ?? NSNull(),
              "image_base64": imageData.base64EncodedString(),
            ]
            return try? JSONSerialization.data(withJSONObject: screenshotObject)
          }
          guard let screenshotData else { continue }

          if hasWrittenScreenshot {
            try file.write(contentsOf: Data(",".utf8))
          }
          try file.write(contentsOf: screenshotData)
          hasWrittenScreenshot = true
        }

        guard hasWrittenScreenshot else {
          try file.close()
          try FileManager.default.removeItem(at: fileURL)
          return nil
        }
        try file.write(contentsOf: Data("]}".utf8))
        try file.close()
      } catch {
        try? file.close()
        throw error
      }
      return fileURL
    } catch {
      try? FileManager.default.removeItem(at: fileURL)
      return nil
    }
  }

  private static func removeStaleUploadFiles() {
    let temporaryDirectory = FileManager.default.temporaryDirectory
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: temporaryDirectory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else { return }

    let staleBefore = Date().addingTimeInterval(-60 * 60)
    for url in urls where url.lastPathComponent.hasPrefix("dayflow-studio-upload-") {
      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
      guard let modified = values?.contentModificationDate, modified < staleBefore else { continue }
      try? FileManager.default.removeItem(at: url)
    }
  }

  private static func importAvailableResults(
    from endpoint: URL,
    store: any StorageManaging,
    completion: ((Int?, Bool) -> Void)? = nil
  ) {
    var request = URLRequest(url: endpoint.appendingPathComponent("v1/results").appending(queryItems: [
      URLQueryItem(name: "device_id", value: deviceID)
    ]))
    request.timeoutInterval = 60
    if let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
      var resultCount: Int?
      var failed = true
      defer { completion?(resultCount, failed) }
      guard InputIdleSnapshot.isIdle() else {
        failed = false
        return
      }
      guard error == nil, let response = response as? HTTPURLResponse,
        (200..<300).contains(response.statusCode), let data,
        let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
      else { return }
      resultCount = results.count
      failed = false
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
        store.updateBatchStatus(
          batchId: batchID,
          status: cards.isEmpty ? "completed_empty" : "completed"
        )
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
