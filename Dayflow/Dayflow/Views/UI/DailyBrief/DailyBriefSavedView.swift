//
//  DailyBriefSavedView.swift
//  Dayflow
//
//  "What you saved": a grid of images the user saved from their briefs.
//  Clicking one shows it large; the X on a tile removes it.
//

import SwiftUI

struct DailyBriefSavedView: View {
  @ObservedObject private var store = DailyBriefStore.shared
  @State private var enlargedItem: DailyBriefSavedItem?

  private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)]

  var body: some View {
    ZStack {
      VStack(alignment: .leading, spacing: 24) {
        Text("What you saved")
          .font(.custom("InstrumentSerif-Regular", size: 34))
          .foregroundStyle(.white)
          .padding(.horizontal, 36)
          .padding(.top, 30)

        if store.savedItems.isEmpty {
          emptyState
        } else {
          grid
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

      if let item = enlargedItem {
        enlarged(item)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.18), value: enlargedItem)
  }

  private var grid: some View {
    ScrollView {
      LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
        ForEach(store.savedItems) { item in
          DailyBriefSavedTile(
            item: item,
            onOpen: { enlargedItem = item },
            onRemove: { store.unsave(item) }
          )
        }
      }
      .padding(.horizontal, 36)
      .padding(.bottom, 36)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "bookmark")
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(.white.opacity(0.7))
      Text("Nothing saved yet")
        .font(.custom("InstrumentSerif-Regular", size: 24))
        .foregroundStyle(.white)
      Text("Open an image in your daily brief and press Save to keep it here.")
        .font(.custom("Figtree", size: 13))
        .foregroundStyle(.white.opacity(0.75))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: 320)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func enlarged(_ item: DailyBriefSavedItem) -> some View {
    ZStack {
      Color.black.opacity(0.45)
        .contentShape(Rectangle())
        .onTapGesture { enlargedItem = nil }

      DailyBriefEnlargedImageContent(
        url: DailyBriefStore.savedImageURL(item),
        caption: item.caption,
        detail: "From \(DailyBriefRouteDates.long(item.sourceDay))",
        isSaved: true,
        onToggleSave: {
          // A saved image can only be un-saved here, which also closes it.
          store.unsave(item)
          enlargedItem = nil
        }
      )
    }
  }
}

private struct DailyBriefSavedTile: View {
  let item: DailyBriefSavedItem
  let onOpen: () -> Void
  let onRemove: () -> Void

  @State private var isHovering = false

  private var captionText: String {
    if let caption = item.caption, !caption.isEmpty { return caption }
    return "Saved image"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(action: onOpen) {
        Color.clear
          .aspectRatio(16 / 11, contentMode: .fit)
          .overlay {
            DailyBriefFileImage(url: DailyBriefStore.savedImageURL(item), contentMode: .fill)
          }
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
          .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
      .overlay(alignment: .topTrailing) {
        if isHovering {
          removeButton
            .padding(6)
            .transition(.opacity)
        }
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(captionText)
          .font(.custom("Figtree", size: 13))
          .foregroundStyle(.white)
          .lineLimit(1)
        Text(DailyBriefRouteDates.short(item.sourceDay))
          .font(.custom("Figtree", size: 11))
          .foregroundStyle(.white.opacity(0.65))
      }
    }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
    }
  }

  private var removeButton: some View {
    Button(action: onRemove) {
      Image(systemName: "xmark")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 22, height: 22)
        .background(Circle().fill(Color.black.opacity(0.55)))
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .help("Remove from saved")
  }
}
