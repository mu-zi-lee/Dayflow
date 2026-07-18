import XCTest

@testable import Dayflow

final class TimelineActivityLoaderTests: XCTestCase {
  func testRecordingProjectionWindowsOnlyIncludesActivePlatforms() {
    let now = Date()
    let timelineDate = now
    let macActivity = activity(
      id: "mac",
      start: now.addingTimeInterval(-5 * 60),
      end: now.addingTimeInterval(5 * 60),
      title: "Mac",
      platform: .macOS
    )

    let windows = TimelineActivityLoader.recordingProjectionWindows(
      for: timelineDate,
      displaySegments: [
        TimelineDisplaySegment(
          activity: macActivity,
          start: macActivity.startTime,
          end: macActivity.endTime
        )
      ],
      activePlatforms: [.macOS],
      now: now
    )

    XCTAssertNotNil(windows[.macOS])
    XCTAssertNil(windows[.android])
  }

  func testRecordingProjectionWindowsAreComputedPerPlatform() {
    let now = Date()
    let timelineDate = now
    let macActivity = activity(
      id: "mac",
      start: now.addingTimeInterval(-5 * 60),
      end: now.addingTimeInterval(5 * 60),
      title: "Mac",
      platform: .macOS
    )
    let androidActivity = activity(
      id: "android",
      start: now.addingTimeInterval(12 * 60),
      end: now.addingTimeInterval(22 * 60),
      title: "Android",
      platform: .android
    )

    let windows = TimelineActivityLoader.recordingProjectionWindows(
      for: timelineDate,
      displaySegments: [
        TimelineDisplaySegment(
          activity: macActivity,
          start: macActivity.startTime,
          end: macActivity.endTime
        ),
        TimelineDisplaySegment(
          activity: androidActivity,
          start: androidActivity.startTime,
          end: androidActivity.endTime
        ),
      ],
      activePlatforms: [.macOS, .android],
      now: now
    )

    XCTAssertNotNil(windows[.macOS])
    XCTAssertNotNil(windows[.android])
    XCTAssertNotEqual(
      windows[.macOS]?.start,
      windows[.android]?.start
    )
  }

  func testResolveDisplaySegmentsGroupsConsecutiveFailures() {
    let activities = [
      activity(
        id: "failure-3", startMinute: 31, endMinute: 46, title: "Processing failed", batchId: 3),
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(
        id: "failure-2", startMinute: 15, endMinute: 30, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.resolveDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 1)
    XCTAssertEqual(segments[0].activity.id, "failure-1")
    XCTAssertEqual(segments[0].failureCount, 3)
    XCTAssertEqual(segments[0].batchIds, [1, 2, 3])
    XCTAssertEqual(segments[0].start, date(minute: 0))
    XCTAssertEqual(segments[0].end, date(minute: 46))
  }

  func testResolveDisplaySegmentsDoesNotGroupAcrossAnotherActivity() {
    let activities = [
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(id: "idle", startMinute: 15, endMinute: 30, title: "Idle"),
      activity(
        id: "failure-2", startMinute: 30, endMinute: 45, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.resolveDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 3)
    XCTAssertEqual(segments.map(\.failureCount), [1, 0, 1])
  }

  func testResolveDisplaySegmentsDoesNotGroupFailuresSeparatedByMoreThanOneMinute() {
    let activities = [
      activity(
        id: "failure-1", startMinute: 0, endMinute: 15, title: "Processing failed", batchId: 1),
      activity(
        id: "failure-2", startMinute: 17, endMinute: 32, title: "Processing failed", batchId: 2),
    ]

    let segments = TimelineActivityLoader.resolveDisplaySegments(from: activities)

    XCTAssertEqual(segments.count, 2)
    XCTAssertEqual(segments.map(\.failureCount), [1, 1])
  }

  private func activity(
    id: String,
    startMinute: Int,
    endMinute: Int,
    title: String,
    platform: CapturePlatform = .macOS,
    batchId: Int64? = nil
  ) -> TimelineActivity {
    activity(
      id: id,
      start: date(minute: startMinute),
      end: date(minute: endMinute),
      title: title,
      platform: platform,
      batchId: batchId
    )
  }

  private func activity(
    id: String,
    start: Date,
    end: Date,
    title: String,
    platform: CapturePlatform = .macOS,
    batchId: Int64? = nil
  ) -> TimelineActivity {
    TimelineActivity(
      id: id,
      recordId: nil,
      batchId: batchId,
      startTime: start,
      endTime: end,
      title: title,
      summary: "",
      detailedSummary: "",
      category: title == "Idle" ? "Idle" : "System",
      subcategory: "",
      distractions: nil,
      videoSummaryURL: nil,
      screenshot: nil,
      appSites: nil,
      isBackupGenerated: false,
      platform: platform
    )
  }

  private func date(minute: Int) -> Date {
    Date(timeIntervalSinceReferenceDate: TimeInterval(minute * 60))
  }
}
