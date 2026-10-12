import AppKit
import Combine
import EventKit
import GRDB

struct CalendarActivity: Equatable, FetchableRecord, Decodable {
  let id: Int64
  let startTs: Double
  let endTs: Double
  let title: String
  let summary: String
  let detailedSummary: String
  let category: String

  var notes: String {
    [category, summary, detailedSummary == summary ? "" : detailedSummary]
      .filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  static func fetchSnapshot(in db: Database, since start: Double) throws -> [CalendarActivity] {
    try fetchAll(db, sql: """
      SELECT id, start_ts AS startTs, end_ts AS endTs, title,
        COALESCE(summary, '') AS summary,
        COALESCE(detailed_summary, '') AS detailedSummary,
        COALESCE(category, '') AS category
      FROM timeline_cards
      WHERE is_deleted = 0 AND start_ts >= ? AND end_ts > start_ts
      ORDER BY start_ts, id
      """, arguments: [start])
  }
}

/// The dedicated calendar is a projection of the database, not a second editable timeline.
@MainActor
final class AppleCalendarSync: ObservableObject {
  static let shared = AppleCalendarSync()

  struct Account: Identifiable {
    let id: String
    let name: String
  }

  @Published private(set) var isEnabled: Bool
  @Published private(set) var isAuthorizing = false
  @Published private(set) var lastSyncAt: Date?
  @Published private(set) var errorMessage: String?
  @Published private(set) var accounts: [Account] = []
  @Published private(set) var calendarName: String?
  @Published var selectedAccountID = ""

  private let store = EKEventStore()
  private let defaults = UserDefaults.standard
  private var observation: AnyDatabaseCancellable?
  private var subscriptions: Set<AnyCancellable> = []
  private var pendingSync: Task<Void, Never>?
  private var activities: [CalendarActivity] = []
  private var hasSnapshot = false
  private var started = false

  private enum Key {
    static let enabled = "appleCalendarSync.enabled"
    static let start = "appleCalendarSync.start"
    static let calendar = "appleCalendarSync.calendar"
    static let owner = "appleCalendarSync.owner"
    static let events = "appleCalendarSync.events"
  }

  private init() {
    isEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
  }

  func start() {
    guard !started else { return }
    started = true
    // Upgrade existing today-only subscriptions to the full timeline as well.
    defaults.set(0.0, forKey: Key.start)
    NotificationCenter.default.publisher(for: .EKEventStoreChanged)
      .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
      .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification))
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.refreshAccounts()
        if self?.isEnabled == true && self?.hasSnapshot == false {
          self?.observeTimeline()
        }
        self?.scheduleSync()
      }
      .store(in: &subscriptions)
    refreshAccounts()
    if isEnabled { observeTimeline() }
  }

  func requestAccess() {
    guard !isAuthorizing else { return }
    isAuthorizing = true
    errorMessage = nil
    Task {
      defer { isAuthorizing = false }
      do {
        guard try await store.requestFullAccessToEvents() else {
          errorMessage = "Calendar access is disabled. Allow Dayflow in System Settings > Privacy & Security > Calendars."
          return
        }
        refreshAccounts()
        if accounts.isEmpty {
          errorMessage = "No writable calendar account is available. Add an account in Apple Calendar."
        }
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  func setEnabled(_ enabled: Bool) {
    if !enabled {
      isEnabled = false
      defaults.set(false, forKey: Key.enabled)
      observation?.cancel()
      observation = nil
      pendingSync?.cancel()
      pendingSync = nil
      hasSnapshot = false
      errorMessage = nil
      return
    }
    guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
      requestAccess()
      return
    }
    do {
      _ = try destinationCalendar(createIfNeeded: true)
      defaults.set(0.0, forKey: Key.start)
      isEnabled = true
      defaults.set(true, forKey: Key.enabled)
      errorMessage = nil
      observeTimeline()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  var hasAccess: Bool {
    EKEventStore.authorizationStatus(for: .event) == .fullAccess
  }

  func syncAllHistory() {
    guard isEnabled, hasAccess else { return }
    defaults.set(0.0, forKey: Key.start)
    errorMessage = nil
    observeTimeline()
  }

  private func refreshAccounts() {
    guard hasAccess else {
      accounts = []
      return
    }
    let writableSources = Set(store.calendars(for: .event)
      .filter { $0.allowsContentModifications }.map { $0.source.sourceIdentifier })
    accounts = store.sources.filter {
      $0.sourceType == .local || ($0.sourceType == .calDAV && writableSources.contains($0.sourceIdentifier))
    }.map { Account(id: $0.sourceIdentifier, name: $0.title) }
    if !accounts.contains(where: { $0.id == selectedAccountID }) {
      selectedAccountID = accounts.first(where: { $0.name.localizedCaseInsensitiveContains("iCloud") })?.id
        ?? accounts.first?.id ?? ""
    }
    if let id = defaults.string(forKey: Key.calendar), let calendar = store.calendar(withIdentifier: id) {
      calendarName = "\(calendar.title) (\(calendar.source.title))"
    }
  }

  private func destinationCalendar(createIfNeeded: Bool) throws -> EKCalendar {
    if let id = defaults.string(forKey: Key.calendar) {
      guard let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications else {
        throw SyncError.destinationUnavailable
      }
      return calendar
    }
    guard createIfNeeded, let source = store.sources.first(where: { $0.sourceIdentifier == selectedAccountID }) else {
      throw SyncError.noAccount
    }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = "Dayflow"
    calendar.source = source
    try store.saveCalendar(calendar, commit: true)
    defaults.set(calendar.calendarIdentifier, forKey: Key.calendar)
    calendarName = "\(calendar.title) (\(source.title))"
    return calendar
  }

  private func observeTimeline() {
    observation?.cancel()
    hasSnapshot = false
    let start = defaults.double(forKey: Key.start)
    let query = ValueObservation.tracking { db in
      try CalendarActivity.fetchSnapshot(in: db, since: start)
    }
    observation = query.start(in: StorageManager.shared.db, onError: { [weak self] error in
      // Never reconcile deletions from a failed or incomplete database read.
      self?.hasSnapshot = false
      self?.errorMessage = error.localizedDescription
    }, onChange: { [weak self] activities in
      self?.activities = activities
      self?.hasSnapshot = true
      self?.scheduleSync()
    })
  }

  private func scheduleSync() {
    guard isEnabled, hasSnapshot else { return }
    pendingSync?.cancel()
    pendingSync = Task {
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
      guard !Task.isCancelled, isEnabled, hasSnapshot else { return }
      synchronize()
    }
  }

  private func synchronize() {
    guard hasAccess else {
      errorMessage = "Calendar access is disabled. Allow Dayflow in System Settings > Privacy & Security > Calendars."
      return
    }
    do {
      let calendar = try destinationCalendar(createIfNeeded: false)
      let owner = defaults.string(forKey: Key.owner) ?? UUID().uuidString.lowercased()
      defaults.set(owner, forKey: Key.owner)
      let prefix = "dayflow-calendar://\(owner)/activity/"
      let previousIDs = defaults.dictionary(forKey: Key.events) as? [String: String] ?? [:]
      var existing: [String: EKEvent] = [:]
      var duplicates: [EKEvent] = []

      // Date queries recover events if a prior save completed before the ID map was persisted.
      // EventKit limits queries to four years; use yearly windows for long-running installations.
      let earliestStart = activities.map(\.startTs).min() ?? Date().timeIntervalSince1970
      var cursor = Date(timeIntervalSince1970: earliestStart).addingTimeInterval(-86400)
      let end = max(Date(), activities.map { Date(timeIntervalSince1970: $0.endTs) }.max() ?? Date())
        .addingTimeInterval(86400)
      var seen: Set<String> = []
      while cursor < end {
        let next = min(Calendar.current.date(byAdding: .year, value: 1, to: cursor) ?? end, end)
        let predicate = store.predicateForEvents(withStart: cursor, end: next, calendars: [calendar])
        for event in store.events(matching: predicate) {
          guard let url = event.url?.absoluteString, url.hasPrefix(prefix),
            let identifier = event.eventIdentifier, seen.insert(identifier).inserted else { continue }
          if existing[url] == nil { existing[url] = event } else { duplicates.append(event) }
        }
        cursor = next
      }
      // Also find managed events moved outside the query window by Calendar edits.
      for identifier in previousIDs.values where !seen.contains(identifier) {
        guard let event = store.event(withIdentifier: identifier),
          event.calendar.calendarIdentifier == calendar.calendarIdentifier,
          let url = event.url?.absoluteString, url.hasPrefix(prefix) else { continue }
        if existing[url] == nil { existing[url] = event } else { duplicates.append(event) }
      }

      var currentIDs: [String: String] = [:]
      var currentEvents: [String: EKEvent] = [:]
      var changed = false
      for activity in activities {
        let url = prefix + String(activity.id)
        let event = existing.removeValue(forKey: url) ?? EKEvent(eventStore: store)
        let start = Date(timeIntervalSince1970: activity.startTs)
        let end = Date(timeIntervalSince1970: activity.endTs)
        let title = activity.title.isEmpty ? "Dayflow activity" : activity.title
        if event.eventIdentifier == nil || event.title != title || event.startDate != start
          || event.endDate != end || event.notes != activity.notes || event.isAllDay
          || !(event.alarms ?? []).isEmpty {
          event.calendar = calendar
          event.title = title
          event.startDate = start
          event.endDate = end
          event.notes = activity.notes
          event.url = URL(string: url)
          event.isAllDay = false
          event.alarms = nil
          try store.save(event, span: .thisEvent, commit: false)
          changed = true
        }
        currentIDs[url] = event.eventIdentifier
        currentEvents[url] = event
      }
      for event in Array(existing.values) + duplicates {
        try store.remove(event, span: .thisEvent, commit: false)
        changed = true
      }
      if changed { try store.commit() }
      // New identifiers become available after commit.
      for (url, event) in currentEvents {
        currentIDs[url] = event.eventIdentifier
      }
      defaults.set(currentIDs, forKey: Key.events)
      lastSyncAt = Date()
      errorMessage = nil
    } catch {
      store.reset()
      errorMessage = error.localizedDescription
    }
  }

  private enum SyncError: LocalizedError {
    case noAccount
    case destinationUnavailable

    var errorDescription: String? {
      switch self {
      case .noAccount: return "Choose a writable calendar account."
      case .destinationUnavailable:
        return "The Dayflow calendar is unavailable or read-only. Restore it or reconnect its account in Apple Calendar."
      }
    }
  }
}
