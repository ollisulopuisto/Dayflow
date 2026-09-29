import Foundation

struct BatchImageExportManifest: Codable {
  let formatVersion: Int
  let exportedAt: Date
  let batches: [Batch]

  struct Batch: Codable {
    let id: Int64
    let startTs: Int
    let endTs: Int
    let status: String
    let screenshots: [ScreenshotEntry]
  }

  struct ScreenshotEntry: Codable {
    let id: Int64
    let capturedAt: Int
    let idleSecondsAtCapture: Int?
    let file: String
  }
}

enum BatchImageExporter {
  static func export(start: Date, end: Date, to destination: URL) throws -> (batches: Int, images: Int) {
    let startTs = Int(start.timeIntervalSince1970)
    let endExclusive = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(86_400)
    let endTs = Int(endExclusive.timeIntervalSince1970) - 1
    let storage = StorageManager.shared
    let batches = storage.allBatches()
      .filter { $0.start <= endTs && $0.end >= startTs }
      .sorted { $0.start < $1.start }

    guard !batches.isEmpty else { throw BatchImageExportError.noBatches }

    let fm = FileManager.default
    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
    var manifestBatches: [BatchImageExportManifest.Batch] = []
    var imageCount = 0

    for batch in batches {
      let screenshots = storage.screenshotsForBatch(batch.id)
      guard !screenshots.isEmpty else { continue }
      let batchFolderName = String(format: "batch-%lld", batch.id)
      let batchFolder = destination.appendingPathComponent(batchFolderName, isDirectory: true)
      try fm.createDirectory(at: batchFolder, withIntermediateDirectories: true)
      var entries: [BatchImageExportManifest.ScreenshotEntry] = []

      for screenshot in screenshots where screenshot.capturedAt >= startTs && screenshot.capturedAt <= endTs {
        let filename = String(format: "screenshot-%lld-%d.jpg", screenshot.id, screenshot.capturedAt)
        let url = batchFolder.appendingPathComponent(filename)
        try screenshot.writeJPEG(to: url, maxHeight: 1440, quality: 0.82)
        entries.append(.init(
          id: screenshot.id,
          capturedAt: screenshot.capturedAt,
          idleSecondsAtCapture: screenshot.idleSecondsAtCapture,
          file: "\(batchFolderName)/\(filename)"
        ))
        imageCount += 1
      }
      if !entries.isEmpty {
        manifestBatches.append(.init(
          id: batch.id, startTs: batch.start, endTs: batch.end, status: batch.status,
          screenshots: entries
        ))
      }
    }

    guard imageCount > 0 else { throw BatchImageExportError.noImages }
    let manifest = BatchImageExportManifest(formatVersion: 1, exportedAt: Date(), batches: manifestBatches)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(manifest).write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
    try instructions.write(to: destination.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    return (manifestBatches.count, imageCount)
  }

  private static let instructions = """
  Dayflow batch image export

  Each batch-NNN folder is one independent analysis job. manifest.json maps each
  JPEG to its original screenshot ID and capture timestamp (Unix seconds).
  Return results keyed by batch ID and screenshot ID so they can be matched back
  to the originating Dayflow database. Images are scaled JPEG copies; originals
  remain on the recording Mac.
  """
}

enum BatchImageExportError: LocalizedError {
  case noBatches
  case noImages

  var errorDescription: String? {
    switch self {
    case .noBatches: return String(localized: "No analysis batches were found in that date range.")
    case .noImages: return String(localized: "No screenshots could be exported from those batches.")
    }
  }
}
