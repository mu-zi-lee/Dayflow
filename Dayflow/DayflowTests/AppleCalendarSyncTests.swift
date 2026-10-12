import GRDB
import XCTest

@testable import Dayflow

final class AppleCalendarSyncTests: XCTestCase {
  private func database() throws -> DatabaseQueue {
    let queue = try DatabaseQueue()
    try queue.write { db in
      try db.execute(sql: """
        CREATE TABLE timeline_cards (
          id INTEGER PRIMARY KEY, start_ts INTEGER, end_ts INTEGER, title TEXT,
          summary TEXT, detailed_summary TEXT, category TEXT, is_deleted INTEGER DEFAULT 0
        )
        """)
    }
    return queue
  }

  func testSnapshotExcludesHistoryDeletedAndInvalidIntervals() throws {
    let queue = try database()
    try queue.write { db in
      try db.execute(sql: """
        INSERT INTO timeline_cards (id, start_ts, end_ts, title, is_deleted) VALUES
          (1, 90, 110, 'History', 0),
          (2, 100, 120, 'Boundary', 0),
          (3, 110, 130, 'Deleted', 1),
          (4, 130, 130, 'Empty', 0),
          (5, 150, 140, 'Reversed', 0)
        """)
    }
    let snapshot = try queue.read { try CalendarActivity.fetchSnapshot(in: $0, since: 100) }
    XCTAssertEqual(snapshot.map(\.id), [2])
    XCTAssertEqual(snapshot.first?.summary, "")
    XCTAssertEqual(snapshot.first?.notes, "")
  }

  func testReanalysisReplacesOldRecordsAndEditsKeepIdentity() throws {
    let queue = try database()
    try queue.write { db in
      try db.execute(sql: """
        INSERT INTO timeline_cards (id, start_ts, end_ts, title) VALUES (1, 100, 120, 'Original')
        """)
    }
    try queue.write { db in
      try db.execute(sql: "UPDATE timeline_cards SET title = 'Edited', end_ts = 125 WHERE id = 1")
    }
    let edited = try queue.read { try CalendarActivity.fetchSnapshot(in: $0, since: 100) }
    XCTAssertEqual(edited.first?.id, 1)
    XCTAssertEqual(edited.first?.title, "Edited")
    XCTAssertEqual(edited.first?.endTs, 125)
    try queue.write { db in
      try db.execute(sql: "UPDATE timeline_cards SET is_deleted = 1 WHERE id = 1")
      try db.execute(sql: """
        INSERT INTO timeline_cards (id, start_ts, end_ts, title) VALUES (2, 100, 130, 'Reanalyzed')
        """)
    }
    let replaced = try queue.read { try CalendarActivity.fetchSnapshot(in: $0, since: 100) }
    XCTAssertEqual(replaced.map(\.id), [2])
  }

  func testSnapshotUsesAbsoluteTimestampsAcrossMidnight() throws {
    let queue = try database()
    let start: Double = 1_792_022_100
    let end = start + 3600
    try queue.write { db in
      try db.execute(sql: """
        INSERT INTO timeline_cards (id, start_ts, end_ts, title, summary, detailed_summary, category)
        VALUES (1, ?, ?, 'Work', 'Summary', 'Details', 'Focus')
        """, arguments: [start, end])
    }
    let snapshot = try queue.read { try CalendarActivity.fetchSnapshot(in: $0, since: start) }
    XCTAssertEqual(snapshot.first?.startTs, start)
    XCTAssertEqual(snapshot.first?.endTs, end)
    XCTAssertEqual(snapshot.first?.notes, "Focus\n\nSummary\n\nDetails")
  }

  func testNotesDoNotRepeatIdenticalDetails() {
    let activity = CalendarActivity(id: 1, startTs: 100, endTs: 200, title: "Work",
      summary: "Summary", detailedSummary: "Summary", category: "")
    XCTAssertEqual(activity.notes, "Summary")
  }

  func testFullHistoryIncludesOldCardsAndExcludesDeletedCards() throws {
    let queue = try database()
    try queue.write { db in
      try db.execute(sql: """
        INSERT INTO timeline_cards (id, start_ts, end_ts, title, is_deleted) VALUES
          (1, 100, 200, 'Old activity', 0),
          (2, 1792022100, 1792025700, 'Recent activity', 0),
          (3, 300, 400, 'Deleted activity', 1)
        """)
    }
    let snapshot = try queue.read { try CalendarActivity.fetchSnapshot(in: $0, since: 0) }
    XCTAssertEqual(snapshot.map(\.id), [1, 2])
  }
}
