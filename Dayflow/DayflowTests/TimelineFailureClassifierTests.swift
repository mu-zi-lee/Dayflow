import XCTest

@testable import Dayflow

final class TimelineFailureClassifierTests: XCTestCase {
  func testFallbackClassificationUsesPrimaryFailure() {
    let primaryError = NSError(
      domain: NSURLErrorDomain,
      code: NSURLErrorTimedOut,
      userInfo: [NSLocalizedDescriptionKey: "The request timed out."]
    )
    let backupError = NSError(
      domain: "ChatCLI",
      code: -4,
      userInfo: [NSLocalizedDescriptionKey: "401 Unauthorized: invalid API key"]
    )

    let classification = TimelineFailureClassifier.classify(
      LLMProviderFallbackError(primaryError: primaryError, backupError: backupError)
    )

    XCTAssertEqual(classification.kind, .transient)
  }

  func testFallbackErrorRetainsBothFailureDescriptions() {
    let primaryError = NSError(
      domain: "Primary",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "primary failed"]
    )
    let backupError = NSError(
      domain: "Backup",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: "backup failed"]
    )

    let description = LLMProviderFallbackError(
      primaryError: primaryError,
      backupError: backupError
    ).localizedDescription

    XCTAssertTrue(description.contains("primary failed"))
    XCTAssertTrue(description.contains("backup failed"))
  }
}
