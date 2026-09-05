import Foundation
import GRDB
import Sentry

extension StorageManager {
  // MARK: - Screenshot Management (new - replaces video chunks)

  /// Returns the URL for a new HEVC segment file inside the recordings folder.
  func nextSegmentURL() -> URL {
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd_HHmmssSSS"
    return root.appendingPathComponent("\(df.string(from: Date())).mp4")
  }

  func importedScreenshotURL(for metadata: CaptureImportMetadata) throws -> URL {
    let safeDeviceId = safeCapturePathComponent(metadata.deviceId)
    let safeCaptureId = safeCapturePathComponent(metadata.captureId)
    guard !safeDeviceId.isEmpty, !safeCaptureId.isEmpty else {
      throw CocoaError(.fileWriteInvalidFileName)
    }

    let date = Date(timeIntervalSince1970: TimeInterval(metadata.capturedAtUTCMS) / 1000)
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: metadata.timezoneId) ?? .current
    formatter.dateFormat = "yyyy-MM-dd"
    let day = formatter.string(from: date)

    formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
    let timestamp = formatter.string(from: date)
    let sequenceSuffix = metadata.sequence.map { String(format: "s%06lld", $0) }
      ?? "c\(safeCaptureId)"

    let directory = root
      .appendingPathComponent("android", isDirectory: true)
      .appendingPathComponent(safeDeviceId, isDirectory: true)
      .appendingPathComponent(day, isDirectory: true)
    try fileMgr.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("\(timestamp)_\(sequenceSuffix).jpg")
  }

  func existingCaptureIds(deviceId: String, captureIds: [String]) -> Set<String> {
    guard !captureIds.isEmpty else { return [] }
    return (try? timedRead("existingCaptureIds") { db in
      let placeholders = Array(repeating: "?", count: captureIds.count).joined(separator: ",")
      var arguments: [(any DatabaseValueConvertible)?] = [deviceId]
      arguments.append(contentsOf: captureIds)
      let values = try String.fetchAll(
        db,
        sql: """
              SELECT capture_id FROM screenshots
              WHERE device_id = ? AND capture_id IN (\(placeholders))
          """,
        arguments: StatementArguments(arguments)
      )
      return Set(values)
    }) ?? []
  }

  private func safeCapturePathComponent(_ value: String) -> String {
    value.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
  }

  /// Records one captured frame. `file_size` stays NULL until the segment is finalized.
  func saveScreenshot(
    segmentPath: String, frameIndex: Int, capturedAt: Date, idleSecondsAtCapture: Int?
  ) -> Int64? {
    let timestamp = Int(capturedAt.timeIntervalSince1970)

    var screenshotId: Int64?
    try? timedWrite("saveScreenshot") { db in
      try db.execute(
        sql: """
              INSERT INTO screenshots(
                captured_at, file_path, frame_index, idle_seconds_at_capture,
                device_id, source_platform, timezone_id, utc_offset_seconds,
                orientation, capture_kind
              )
              VALUES (?, ?, ?, ?, ?, 'macos', ?, ?, 'unknown', 'image')
          """,
        arguments: [
          timestamp, segmentPath, frameIndex, idleSecondsAtCapture, LocalCaptureDevice.id,
          TimeZone.current.identifier, TimeZone.current.secondsFromGMT(for: capturedAt),
        ])
      screenshotId = db.lastInsertedRowID
    }
    return screenshotId
  }

  func saveImportedScreenshot(url: URL, metadata: CaptureImportMetadata) throws -> Int64 {
    let storedFileSize = metadata.byteLength ?? {
      let attributes = try? fileMgr.attributesOfItem(atPath: url.path)
      return (attributes?[.size] as? NSNumber)?.int64Value
    }()

    return try insertImportedCapture(
      filePath: url.path,
      fileSize: storedFileSize,
      metadata: metadata
    )
  }

  func saveImportedCapture(metadata: CaptureImportMetadata) throws -> Int64 {
    guard metadata.kind == .redacted else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return try insertImportedCapture(filePath: "", fileSize: nil, metadata: metadata)
  }

  private func insertImportedCapture(
    filePath: String,
    fileSize: Int64?,
    metadata: CaptureImportMetadata
  ) throws -> Int64 {
    let timestamp = Int(metadata.capturedAtUTCMS / 1000)

    return try timedWrite("saveImportedScreenshot") { db in
      if let existing = try Int64.fetchOne(
        db,
        sql: "SELECT id FROM screenshots WHERE device_id = ? AND capture_id = ?",
        arguments: [metadata.deviceId, metadata.captureId]
      ) {
        return existing
      }

      try db.execute(
        sql: """
              INSERT INTO screenshots(
                captured_at, file_path, file_size, idle_seconds_at_capture,
                capture_id, device_id, source_platform, session_id, sequence,
                timezone_id, utc_offset_seconds, foreground_app_id, foreground_app_name,
                orientation, pixel_width, pixel_height, capture_kind, content_sha256,
                received_at
              ) VALUES (?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          timestamp, filePath, fileSize, metadata.captureId, metadata.deviceId,
          metadata.platform.rawValue, metadata.sessionId, metadata.sequence,
          metadata.timezoneId, metadata.utcOffsetSeconds, metadata.foregroundAppId,
          metadata.foregroundAppName, metadata.orientation.rawValue, metadata.pixelWidth,
          metadata.pixelHeight, metadata.kind.rawValue, metadata.sha256,
          Int(Date().timeIntervalSince1970),
        ]
      )
      return db.lastInsertedRowID
    }
  }

  /// Spreads a finalized segment's byte count evenly across its frames so purge accounting works per row.
  func updateScreenshotFileSizes(segmentPath: String, totalBytes: Int64) {
    try? timedWrite("updateScreenshotFileSizes") { db in
      let frameCount =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM screenshots WHERE file_path = ?", arguments: [segmentPath])
        ?? 0
      guard frameCount > 0 else { return }
      let perFrame = max(1, totalBytes / Int64(frameCount))
      try db.execute(
        sql: "UPDATE screenshots SET file_size = ? WHERE file_path = ?",
        arguments: [perFrame, segmentPath])
    }
  }

  /// Soft-deletes every frame of a segment (used when the segment file is lost or corrupt).
  func markScreenshotsDeleted(segmentPath: String) {
    try? timedWrite("markScreenshotsDeleted") { db in
      try db.execute(
        sql: "UPDATE screenshots SET is_deleted = 1 WHERE file_path = ?",
        arguments: [segmentPath])
    }
  }

  /// Path of the newest segment that still has live frames, for crash recovery at launch.
  func mostRecentSegmentPath() -> String? {
    try? timedRead("mostRecentSegmentPath") { db in
      try String.fetchOne(
        db,
        sql: """
              SELECT file_path FROM screenshots
              WHERE is_deleted = 0 AND frame_index IS NOT NULL
              ORDER BY captured_at DESC LIMIT 1
          """)
    }
  }

  /// Observed recording rate in bytes per hour over finalized frames captured since `since`.
  /// Returns nil until at least ten minutes of finalized frames exist.
  func observedRecordingBytesPerHour(since: Date) -> Int64? {
    let sinceTs = Int(since.timeIntervalSince1970)
    let row = try? timedRead("observedRecordingBytesPerHour") { db in
      try Row.fetchOne(
        db,
        sql: """
              SELECT SUM(file_size) AS bytes, MIN(captured_at) AS first_ts, MAX(captured_at) AS last_ts
              FROM screenshots
              WHERE captured_at >= ? AND is_deleted = 0 AND file_size IS NOT NULL
                AND COALESCE(source_platform, 'macos') = 'macos'
          """, arguments: [sinceTs])
    }
    guard let row, let bytes: Int64 = row["bytes"],
      let firstTs: Int = row["first_ts"], let lastTs: Int = row["last_ts"]
    else { return nil }
    let spanSeconds = lastTs - firstTs
    guard spanSeconds >= 600 else { return nil }
    return Int64(Double(bytes) * 3600 / Double(spanSeconds))
  }

  func screenshot(from row: Row) -> Screenshot {
    let platformRaw: String = row["source_platform"] ?? CapturePlatform.macOS.rawValue
    let orientationRaw: String = row["orientation"] ?? CaptureOrientation.unknown.rawValue
    let kindRaw: String = row["capture_kind"] ?? CaptureKind.image.rawValue
    return Screenshot(
      id: row["id"],
      capturedAt: row["captured_at"],
      filePath: row["file_path"],
      fileSize: row["file_size"],
      idleSecondsAtCapture: row["idle_seconds_at_capture"],
      isDeleted: (row["is_deleted"] as? Int ?? 0) != 0,
      frameIndex: row["frame_index"],
      captureId: row["capture_id"],
      deviceId: row["device_id"] ?? LocalCaptureDevice.id,
      platform: CapturePlatform(rawValue: platformRaw) ?? .macOS,
      sessionId: row["session_id"],
      sequence: row["sequence"],
      timezoneId: row["timezone_id"],
      utcOffsetSeconds: row["utc_offset_seconds"],
      foregroundAppId: row["foreground_app_id"],
      foregroundAppName: row["foreground_app_name"],
      orientation: CaptureOrientation(rawValue: orientationRaw) ?? .unknown,
      pixelWidth: row["pixel_width"],
      pixelHeight: row["pixel_height"],
      kind: CaptureKind(rawValue: kindRaw) ?? .image,
      contentSHA256: row["content_sha256"]
    )
  }

  func fetchUnprocessedScreenshots(since oldestTimestamp: Int) -> [Screenshot] {
    (try? timedRead("fetchUnprocessedScreenshots") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT * FROM screenshots
              WHERE captured_at >= ?
                AND is_deleted = 0
                AND id NOT IN (SELECT screenshot_id FROM batch_screenshots)
              ORDER BY captured_at ASC
          """, arguments: [oldestTimestamp]
      )
      .map(screenshot(from:))
    }) ?? []
  }

  func saveBatchWithScreenshots(startTs: Int, endTs: Int, screenshotIds: [Int64]) -> Int64? {
    guard !screenshotIds.isEmpty else { return nil }
    var batchId: Int64 = 0

    try? timedWrite("saveBatchWithScreenshots(\(screenshotIds.count))") { db in
      let placeholders = Array(repeating: "?", count: screenshotIds.count).joined(separator: ",")
      let sources = try Row.fetchAll(
        db,
        sql: """
              SELECT DISTINCT device_id, source_platform
              FROM screenshots
              WHERE id IN (\(placeholders))
          """,
        arguments: StatementArguments(screenshotIds)
      )
      guard sources.count == 1,
        let deviceId: String = sources[0]["device_id"],
        let sourcePlatform: String = sources[0]["source_platform"]
      else {
        return
      }

      try db.execute(
        sql: """
              INSERT INTO analysis_batches(
                batch_start_ts, batch_end_ts, device_id, source_platform
              ) VALUES (?, ?, ?, ?)
          """, arguments: [startTs, endTs, deviceId, sourcePlatform])
      batchId = db.lastInsertedRowID

      for id in screenshotIds {
        try db.execute(
          sql: """
                INSERT INTO batch_screenshots(batch_id, screenshot_id)
                VALUES (?, ?)
            """, arguments: [batchId, id])
      }
    }
    return batchId == 0 ? nil : batchId
  }

  func screenshotsForBatch(_ batchId: Int64) -> [Screenshot] {
    (try? timedRead("screenshotsForBatch") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT s.* FROM batch_screenshots bs
              JOIN screenshots s ON s.id = bs.screenshot_id
              WHERE bs.batch_id = ?
                AND s.is_deleted = 0
              ORDER BY s.captured_at ASC
          """, arguments: [batchId]
      )
      .map(screenshot(from:))
    }) ?? []
  }

  func deviceIdForBatch(_ batchId: Int64) -> String? {
    try? timedRead("deviceIdForBatch") { db in
      try String.fetchOne(
        db,
        sql: "SELECT device_id FROM analysis_batches WHERE id = ?",
        arguments: [batchId]
      )
    }
  }

  func fetchScreenshotsInTimeRange(startTs: Int, endTs: Int) -> [Screenshot] {
    fetchScreenshotsInTimeRange(startTs: startTs, endTs: endTs, deviceId: nil)
  }

  func fetchScreenshotsInTimeRange(startTs: Int, endTs: Int, deviceId: String?) -> [Screenshot] {
    (try? timedRead("fetchScreenshotsInTimeRange") { db in
      let deviceClause = deviceId == nil ? "" : "AND device_id = ?"
      var arguments: [(any DatabaseValueConvertible)?] = [startTs, endTs]
      if let deviceId { arguments.append(deviceId) }
      return try Row.fetchAll(
        db,
        sql: """
              SELECT * FROM screenshots
              WHERE captured_at >= ? AND captured_at <= ?
                AND is_deleted = 0
                \(deviceClause)
              ORDER BY captured_at ASC
          """, arguments: StatementArguments(arguments)
      )
      .map(screenshot(from:))
    }) ?? []
  }

}
