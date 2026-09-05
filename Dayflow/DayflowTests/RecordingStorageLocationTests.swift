import XCTest
@testable import Dayflow

final class RecordingStorageLocationTests: XCTestCase {
  func testDestinationAddsDayflowRecordingsSubdirectory() {
    let selected = URL(fileURLWithPath: "/tmp/Box", isDirectory: true)

    let destination = RecordingStorageLocation.destinationURL(inside: selected)

    XCTAssertEqual(destination.path, "/tmp/Box/Dayflow/recordings")
  }

  func testDefaultLocationUsesApplicationSupportDirectory() {
    let fileManager = FileManager.default
    let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]

    let destination = RecordingStorageLocation.defaultRecordingsURL(fileManager: fileManager)

    XCTAssertEqual(
      destination.standardizedFileURL,
      applicationSupport
        .appendingPathComponent("Dayflow/recordings", isDirectory: true)
        .standardizedFileURL
    )
  }
}
