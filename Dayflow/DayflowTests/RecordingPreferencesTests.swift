import XCTest

@testable import Dayflow

final class RecordingPreferencesTests: XCTestCase {
  func testCaptureIntervalsIncludeThreeSecondOptionBetweenOneAndFiveSeconds() {
    XCTAssertEqual(Array(ScreenshotConfig.intervalOptions.prefix(3)), [1, 3, 5])
  }
}
