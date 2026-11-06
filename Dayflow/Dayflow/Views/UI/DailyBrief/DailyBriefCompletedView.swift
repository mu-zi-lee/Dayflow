//
//  DailyBriefCompletedView.swift
//  Dayflow
//
//  "Everything you completed": every completed item from past briefs,
//  grouped by the day the work happened, plus "Summarize for my review",
//  which asks Claude for a range summary (DailyBriefRangeSummaryView).
//

import SwiftUI

struct DailyBriefCompletedView: View {
  @ObservedObject private var store = DailyBriefStore.shared
  @State private var entries: [DailyBriefCompletedEntry] = []
  @State private var lastRequestedRange: DailyBriefSummaryRange = .last30Days

  private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 10)]

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header
        .padding(.horizontal, 36)
        .padding(.top, 30)
        // Leaves room for the route's close button in the corner.
        .padding(.trailing, 30)

      if case .failed(let message) = store.summaryState {
        failureBanner(message)
          .padding(.horizontal, 36)
      }

      if case .running(let range) = store.summaryState {
        DailyBriefSummarizingView(range: range, entries: entries)
      } else if entries.isEmpty {
        emptyState
      } else {
        entryList
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      entries = store.completedEntries()
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      Text("Everything you completed")
        .font(.custom("InstrumentSerif-Regular", size: 34))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)

      Spacer(minLength: 12)

      existingSummaryLinks
      summarizeMenu
    }
  }

  /// "View" buttons for ranges that already have a summary.
  @ViewBuilder
  private var existingSummaryLinks: some View {
    let ready = DailyBriefSummaryRange.allCases.filter { store.summaries[$0] != nil }
    if !ready.isEmpty, !isSummarizing {
      Menu {
        ForEach(ready) { range in
          Button("View \(range.label.lowercased())") {
            store.route = .rangeSummary(range)
          }
        }
      } label: {
        DailyBriefRoutePill(title: "View", systemImage: "doc.text", isProminent: false)
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .pointingHandCursor()
    }
  }

  private var summarizeMenu: some View {
    Menu {
      ForEach(DailyBriefSummaryRange.allCases) { range in
        Button(range.label) { summarize(range) }
      }
    } label: {
      DailyBriefRoutePill(
        title: isSummarizing ? "Summarizing…" : "Summarize for my review",
        systemImage: isSummarizing ? nil : "chevron.down"
      )
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .disabled(isSummarizing)
    .pointingHandCursor()
  }

  private var isSummarizing: Bool {
    if case .running = store.summaryState { return true }
    return false
  }

  private func summarize(_ range: DailyBriefSummaryRange) {
    lastRequestedRange = range
    store.summarize(range)
  }

  private func failureBanner(_ message: String) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 13))
        .foregroundStyle(Color(hex: "FFB38A"))

      Text(message)
        .font(.custom("Figtree", size: 13))
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 8)

      Button {
        summarize(lastRequestedRange)
      } label: {
        DailyBriefRoutePill(title: "Try again")
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
  }

  // MARK: Entries

  private var entryList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 22) {
        ForEach(groupedDays, id: \.day) { group in
          VStack(alignment: .leading, spacing: 10) {
            Text(DailyBriefRouteDates.long(group.day))
              .font(.custom("Figtree", size: 17).weight(.medium))
              .foregroundStyle(.white)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
              ForEach(group.entries) { entry in
                DailyBriefHistoryCard(entry: entry)
              }
            }
          }
        }
      }
      .padding(.horizontal, 36)
      .padding(.bottom, 36)
    }
  }

  /// Entries grouped by day, newest day first.
  private var groupedDays: [(day: String, entries: [DailyBriefCompletedEntry])] {
    let byDay = Dictionary(grouping: entries, by: \.day)
    return byDay.keys.sorted(by: >).map { day in (day: day, entries: byDay[day] ?? []) }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Text("Nothing here yet")
        .font(.custom("InstrumentSerif-Regular", size: 24))
        .foregroundStyle(.white)
      Text("Each morning's brief adds what you finished the day before.")
        .font(.custom("Figtree", size: 13))
        .foregroundStyle(.white.opacity(0.75))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: 320)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Card

/// One completed item: project, title, app chips, and the work's screenshot
/// peeking in from the bottom-right corner.
private struct DailyBriefHistoryCard: View {
  let entry: DailyBriefCompletedEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let project = entry.item.project, !project.isEmpty {
        Text(project)
          .font(.custom("Figtree", size: 12))
          .foregroundStyle(Color(hex: "8A8580"))
          .lineLimit(1)
      }
      Text(entry.item.title)
        .font(.custom("Figtree", size: 13))
        .foregroundStyle(Color(hex: "1F1B18"))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)

      HStack(spacing: -4) {
        ForEach(entry.item.apps ?? [], id: \.self) { app in
          DailyBriefAppIcon(app: app, size: 14)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.white))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .help(DailyBriefApps.displayName(app))
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .frame(height: 140)
    .background(alignment: .bottomTrailing) {
      // Sits behind the text and app chips, cut off by the card's bottom edge.
      if let url = entry.imageURL {
        DailyBriefFileImage(url: url, contentMode: .fill)
          .frame(width: 140, height: 84)
          .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
          )
          .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
          .offset(x: -14, y: 18)
      }
    }
    .background(
      LinearGradient(
        colors: [Color.white, Color(hex: "EEF0F4")],
        startPoint: .top, endPoint: .bottom)
    )
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(Color.white.opacity(0.7), lineWidth: 0.75)
    )
    .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
  }
}

// MARK: - Summarizing

/// Shown while Claude writes the summary: a small fanned stack of completed
/// cards that rocks gently, and a shimmering serif line.
private struct DailyBriefSummarizingView: View {
  let range: DailyBriefSummaryRange
  let entries: [DailyBriefCompletedEntry]

  @State private var isRocking = false

  private var stackEntries: [DailyBriefCompletedEntry] {
    let withImages = entries.filter { $0.imageURL != nil }
    return Array((withImages.isEmpty ? entries : withImages).prefix(3))
  }

  var body: some View {
    VStack(spacing: 28) {
      Spacer()

      if !stackEntries.isEmpty {
        ZStack {
          ForEach(Array(stackEntries.enumerated()), id: \.element.id) { index, entry in
            DailyBriefHistoryCard(entry: entry)
              .frame(width: 240)
              .rotationEffect(.degrees(cardAngle(index)))
              .offset(y: CGFloat(index) * -6)
              .zIndex(Double(stackEntries.count - index))
          }
        }
        .frame(height: 180)
      }

      DailyBriefSummaryShimmerText(text: "Summarizing your \(range.label.lowercased())…")

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
        isRocking = true
      }
    }
  }

  private func cardAngle(_ index: Int) -> Double {
    let resting: [Double] = [-4, 5, -9]
    let swing: Double = isRocking ? 2.5 : -2.5
    return resting[index % resting.count] + (index == 0 ? swing : -swing / 2)
  }
}

/// Serif text with a soft highlight sweeping across it.
private struct DailyBriefSummaryShimmerText: View {
  let text: String
  @State private var phase: CGFloat = -1

  var body: some View {
    Text(text)
      .font(.custom("InstrumentSerif-Regular", size: 28))
      .foregroundStyle(.white.opacity(0.55))
      .overlay {
        GeometryReader { proxy in
          LinearGradient(
            colors: [.clear, .white, .clear],
            startPoint: .leading, endPoint: .trailing
          )
          .frame(width: proxy.size.width * 0.5)
          .offset(x: phase * proxy.size.width)
        }
        .mask(
          Text(text)
            .font(.custom("InstrumentSerif-Regular", size: 28))
        )
      }
      .onAppear {
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
          phase = 1.2
        }
      }
  }
}
