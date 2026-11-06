//
//  DailyBriefHeatmap.swift
//  Dayflow
//
//  The activity strip under the brief's painting: one row of small squares per
//  category, one column per time slot, for the day the brief was built from.
//  The window is fitted to the activity, from just before the first card to
//  just after the last one.
//

import SwiftUI

struct DailyBriefHeatmap: View {
  /// yyyy-MM-dd, usually the brief's sourceDay.
  let day: String

  @ObservedObject private var categoryStore = CategoryStore.shared
  @Environment(\.dayflowTheme) private var theme
  @State private var cards: [TimelineCard] = []

  private let cellGap: CGFloat = 3
  private let cellHeight: CGFloat = 12

  var body: some View {
    let model = HeatmapModel(cards: cards, categories: categoryStore.categories)

    VStack(alignment: .leading, spacing: 10) {
      legend(model.rows)
      if !model.rows.isEmpty {
        grid(model)
      }
    }
    .task(id: day) {
      let dayToLoad = day
      let loaded = await Task.detached(priority: .utility) {
        StorageManager.shared.fetchTimelineCards(forDay: dayToLoad)
      }.value
      cards = loaded
    }
  }

  // MARK: Legend

  private func legend(_ rows: [HeatmapRow]) -> some View {
    HStack(spacing: 12) {
      ForEach(rows) { row in
        HStack(spacing: 4) {
          Circle()
            .fill(row.color)
            .frame(width: 6, height: 6)
          Text(row.name)
            .font(DailyBriefFonts.sans(10, weight: .medium))
            .foregroundStyle(theme.isDark ? theme.textTertiary : Color(hex: "777777"))
        }
      }
    }
    .frame(height: 12)
  }

  // MARK: Grid

  private func grid(_ model: HeatmapModel) -> some View {
    GeometryReader { geometry in
      let columns = model.slotCount
      let cellWidth = max(
        2, (geometry.size.width - cellGap * CGFloat(columns - 1)) / CGFloat(columns))

      VStack(alignment: .leading, spacing: cellGap) {
        ForEach(model.rows) { row in
          HStack(spacing: cellGap) {
            ForEach(0..<columns, id: \.self) { column in
              RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(cellColor(row: row, column: column))
                .frame(width: cellWidth, height: cellHeight)
            }
          }
        }

        hourLabels(model, cellWidth: cellWidth)
      }
    }
    .frame(height: gridHeight(rowCount: model.rows.count))
  }

  private func cellColor(row: HeatmapRow, column: Int) -> Color {
    let fraction = row.coverage[column]
    guard fraction > 0 else { return theme.dailyEmptyCell }
    return row.color.opacity(0.35 + 0.65 * fraction)
  }

  private func hourLabels(_ model: HeatmapModel, cellWidth: CGFloat) -> some View {
    let slotWidth = cellWidth + cellGap
    return ZStack(alignment: .topLeading) {
      ForEach(model.hourMarks, id: \.self) { minute in
        Text(Self.hourLabel(minute))
          .font(DailyBriefFonts.sans(9))
          .foregroundStyle(theme.isDark ? theme.textTertiary : Color(hex: "9D9D9D"))
          .fixedSize()
          .offset(x: CGFloat(minute - model.startMinute) / CGFloat(model.slotMinutes) * slotWidth)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: 12)
    .padding(.top, 4)
  }

  private func gridHeight(rowCount: Int) -> CGFloat {
    CGFloat(rowCount) * (cellHeight + cellGap) + 16
  }

  /// 600 → "10am", 780 → "1pm", 1440 → "12am".
  static func hourLabel(_ minuteOfDay: Int) -> String {
    let hour = (minuteOfDay / 60) % 24
    let suffix = hour < 12 ? "am" : "pm"
    let display = hour % 12 == 0 ? 12 : hour % 12
    return "\(display)\(suffix)"
  }
}

// MARK: - Model

private struct HeatmapRow: Identifiable {
  let name: String
  let color: Color
  /// Fraction (0...1) of each time slot covered by this category.
  var coverage: [Double]

  var id: String { name }
}

/// Turns timeline cards into rows of slot coverage. Minutes are counted from
/// midnight of the day; times after midnight (before 4am) roll past 1440.
private struct HeatmapModel {
  var rows: [HeatmapRow] = []
  var startMinute = 0
  var slotMinutes = 10
  var slotCount = 1
  var hourMarks: [Int] = []

  init(cards: [TimelineCard], categories: [TimelineCategory]) {
    let spans = cards.compactMap(Self.span)
      .filter { !Self.isIdle($0.category, categories: categories) }
    guard let first = spans.map(\.start).min(), let last = spans.map(\.end).max() else { return }

    // Start 15–30 minutes before the first card, on a half hour. End 15 minutes after the last.
    startMinute = ((first - 15) / 30) * 30
    let endMinute = last + 15
    let length = max(endMinute - startMinute, 60)

    // Keep roughly 60–100 columns whatever the length of the day.
    slotMinutes = [5, 10, 15, 20, 30].first { length / $0 <= 100 } ?? 30
    slotCount = Int((Double(length) / Double(slotMinutes)).rounded(.up))

    hourMarks = stride(from: ((startMinute + 59) / 60) * 60, to: startMinute + length, by: 60)
      .map { $0 }

    rows = Self.makeRows(
      spans: spans, categories: categories, startMinute: startMinute,
      slotMinutes: slotMinutes, slotCount: slotCount)
  }

  private struct Span {
    let category: String
    let start: Int
    let end: Int
  }

  private static func span(_ card: TimelineCard) -> Span? {
    guard var start = parseTimeHMMA(timeString: card.startTimestamp),
      var end = parseTimeHMMA(timeString: card.endTimestamp)
    else { return nil }
    // The logical day starts at 4am, so early-morning times belong to the night before.
    if start < 240 { start += 1440 }
    if end < 240 { end += 1440 }
    if end <= start { end = start + 1 }
    return Span(category: card.category, start: start, end: end)
  }

  private static func normalized(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func isIdle(_ name: String, categories: [TimelineCategory]) -> Bool {
    if normalized(name) == "idle" { return true }
    return categories.contains { $0.isIdle && normalized($0.name) == normalized(name) }
  }

  private static func makeRows(
    spans: [Span], categories: [TimelineCategory], startMinute: Int, slotMinutes: Int,
    slotCount: Int
  ) -> [HeatmapRow] {
    var rowsByName: [String: HeatmapRow] = [:]

    for span in spans {
      let key = normalized(span.category)
      if rowsByName[key] == nil {
        let category = categories.first { normalized($0.name) == key }
        rowsByName[key] = HeatmapRow(
          name: category?.name ?? span.category,
          color: Color(hex: category?.colorHex ?? "B4B4B4"),
          coverage: Array(repeating: 0, count: slotCount))
      }

      for slot in 0..<slotCount {
        let slotStart = startMinute + slot * slotMinutes
        let slotEnd = slotStart + slotMinutes
        let overlap = min(span.end, slotEnd) - max(span.start, slotStart)
        if overlap > 0 {
          let added = Double(overlap) / Double(slotMinutes)
          rowsByName[key]!.coverage[slot] = min(1, rowsByName[key]!.coverage[slot] + added)
        }
      }
    }

    // Same order as the user's category list; unknown categories go last.
    func order(_ row: HeatmapRow) -> Int {
      categories.first { normalized($0.name) == normalized(row.name) }?.order ?? Int.max
    }
    return rowsByName.values.sorted { (order($0), $0.name) < (order($1), $1.name) }
  }
}
