import Foundation
import GRDB

enum RecordingStorageLocation {
  private static let bookmarkKey = "recordingStorageBookmark"
  private static let pathKey = "recordingStoragePath"

  static func defaultRecordingsURL(fileManager: FileManager = .default) -> URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Dayflow/recordings", isDirectory: true)
  }

  static func configuredRecordingsURL(fileManager: FileManager = .default) -> URL {
    let defaults = UserDefaults.standard

    if let bookmark = defaults.data(forKey: bookmarkKey) {
      var isStale = false
      if let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ) {
        _ = url.startAccessingSecurityScopedResource()
        if isStale {
          try? storeCustomURL(url)
        }
        return url.standardizedFileURL
      }
    }

    if let path = defaults.string(forKey: pathKey), !path.isEmpty {
      return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    return defaultRecordingsURL(fileManager: fileManager).standardizedFileURL
  }

  static func destinationURL(inside selectedDirectory: URL) -> URL {
    selectedDirectory.standardizedFileURL
      .appendingPathComponent("Dayflow", isDirectory: true)
      .appendingPathComponent("recordings", isDirectory: true)
  }

  static func storeCustomURL(_ url: URL) throws {
    let standardized = url.standardizedFileURL
    let bookmark = try bookmarkData(for: standardized)
    storeCustomURL(standardized, bookmark: bookmark)
  }

  static func bookmarkData(for url: URL) throws -> Data {
    try url.standardizedFileURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  static func storeCustomURL(_ url: URL, bookmark: Data) {
    let standardized = url.standardizedFileURL
    let defaults = UserDefaults.standard
    defaults.set(bookmark, forKey: bookmarkKey)
    defaults.set(standardized.path, forKey: pathKey)
  }

  static func useDefault() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: bookmarkKey)
    defaults.removeObject(forKey: pathKey)
  }
}

enum RecordingStorageMigrationError: LocalizedError {
  case destinationInsideSource
  case destinationNotEmpty(String)
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .destinationInsideSource:
      return "Choose a folder outside the current recordings folder."
    case .destinationNotEmpty(let path):
      return "The destination already contains files: \(path)"
    case .verificationFailed:
      return "The copied recordings could not be verified. The original files were kept."
    }
  }
}

extension StorageManager {
  func withRecordingStorageAccess<T>(_ operation: () throws -> T) rethrows -> T {
    recordingStorageLock.lock()
    defer { recordingStorageLock.unlock() }
    return try operation()
  }

  func relocateRecordings(inside selectedDirectory: URL) throws -> URL {
    let destination = RecordingStorageLocation.destinationURL(inside: selectedDirectory)
    return try relocateRecordings(to: destination, useDefaultLocation: false)
  }

  func restoreDefaultRecordingsLocation() throws -> URL {
    try relocateRecordings(
      to: RecordingStorageLocation.defaultRecordingsURL(fileManager: fileMgr),
      useDefaultLocation: true
    )
  }

  private func relocateRecordings(to destinationURL: URL, useDefaultLocation: Bool) throws -> URL {
    try FrameStore.shared.withExclusiveWriterAccess {
      try withRecordingStorageAccess {
        let source = _root.standardizedFileURL
        let destination = destinationURL.standardizedFileURL
        guard source.path != destination.path else { return source }

        let sourcePrefix = source.path + "/"
        let destinationPrefix = destination.path + "/"
        guard !destinationPrefix.hasPrefix(sourcePrefix), !sourcePrefix.hasPrefix(destinationPrefix)
        else {
          throw RecordingStorageMigrationError.destinationInsideSource
        }

        let destinationExisted = fileMgr.fileExists(atPath: destination.path)
        if destinationExisted {
          let contents = try fileMgr.contentsOfDirectory(atPath: destination.path)
          guard contents.isEmpty else {
            throw RecordingStorageMigrationError.destinationNotEmpty(destination.path)
          }
        } else {
          try fileMgr.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        do {
          let sourceItems =
            (try? fileMgr.contentsOfDirectory(
              at: source,
              includingPropertiesForKeys: nil,
              options: []
            )) ?? []

          for item in sourceItems {
            try fileMgr.copyItem(
              at: item,
              to: destination.appendingPathComponent(item.lastPathComponent)
            )
          }

          guard try recordingManifest(at: source) == recordingManifest(at: destination) else {
            throw RecordingStorageMigrationError.verificationFailed
          }

          let customBookmark =
            useDefaultLocation ? nil : try RecordingStorageLocation.bookmarkData(for: destination)

          try updateRecordingPaths(
            fromRoot: source.path,
            toRoot: destination.path
          )

          _root = destination
          if useDefaultLocation {
            RecordingStorageLocation.useDefault()
          } else if let customBookmark {
            RecordingStorageLocation.storeCustomURL(destination, bookmark: customBookmark)
          }

          for item in sourceItems {
            do {
              try fileMgr.removeItem(at: item)
            } catch {
              print("⚠️ Recording migration left an original copy at \(item.path): \(error)")
            }
          }
          try? fileMgr.removeItem(at: source)
          return destination
        } catch {
          if !destinationExisted {
            try? fileMgr.removeItem(at: destination)
          } else if let copiedItems = try? fileMgr.contentsOfDirectory(
            at: destination, includingPropertiesForKeys: nil)
          {
            for item in copiedItems {
              try? fileMgr.removeItem(at: item)
            }
          }
          throw error
        }
      }
    }
  }

  private func updateRecordingPaths(fromRoot: String, toRoot: String) throws {
    let oldPrefix = fromRoot + "/"
    let newPrefix = toRoot + "/"
    let prefixLength = oldPrefix.count

    try timedWrite("relocateRecordingPaths") { db in
      try updatePathColumn(
        table: "screenshots",
        column: "file_path",
        oldRoot: fromRoot,
        newRoot: toRoot,
        oldPrefix: oldPrefix,
        newPrefix: newPrefix,
        prefixLength: prefixLength,
        db: db
      )
      try updatePathColumn(
        table: "chunks",
        column: "file_url",
        oldRoot: fromRoot,
        newRoot: toRoot,
        oldPrefix: oldPrefix,
        newPrefix: newPrefix,
        prefixLength: prefixLength,
        db: db
      )
    }
  }

  private func updatePathColumn(
    table: String,
    column: String,
    oldRoot: String,
    newRoot: String,
    oldPrefix: String,
    newPrefix: String,
    prefixLength: Int,
    db: Database
  ) throws {
    try db.execute(
      sql: "UPDATE \(table) SET \(column) = ? WHERE \(column) = ?",
      arguments: [newRoot, oldRoot]
    )
    try db.execute(
      sql: """
            UPDATE \(table)
            SET \(column) = ? || substr(\(column), ?)
            WHERE substr(\(column), 1, ?) = ?
        """,
      arguments: [newPrefix, prefixLength + 1, prefixLength, oldPrefix]
    )
  }

  private func recordingManifest(at directory: URL) throws -> [String: Int64] {
    guard fileMgr.fileExists(atPath: directory.path) else { return [:] }
    guard
      let enumerator = fileMgr.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
        options: []
      )
    else { return [:] }

    var manifest: [String: Int64] = [:]
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard values.isRegularFile == true else { continue }
      let relativePath = String(url.path.dropFirst(directory.path.count + 1))
      manifest[relativePath] = Int64(values.fileSize ?? 0)
    }
    return manifest
  }
}
