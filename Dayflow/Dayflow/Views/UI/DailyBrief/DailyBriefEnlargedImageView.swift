//
//  DailyBriefEnlargedImageView.swift
//  Dayflow
//
//  A brief image shown large ("Recent site-seeing · enlarged image" in Figma),
//  with its caption and a Save / Saved toggle. The close X comes from
//  DailyBriefOverlay's route layer.
//

import SwiftUI

/// Enlarged view for an image that is part of a brief.
struct DailyBriefEnlargedImageView: View {
  @ObservedObject private var store = DailyBriefStore.shared
  let image: DailyBriefImage

  var body: some View {
    DailyBriefEnlargedImageContent(
      url: image.url,
      caption: image.caption,
      detail: DailyBriefRouteDates.long(image.day),
      isSaved: store.isSaved(image),
      onToggleSave: toggleSave
    )
    .onAppear {
      store.recordFeedback(image.section, image.caption ?? image.file, .expanded)
    }
  }

  private func toggleSave() {
    if let savedItem = store.savedItems.first(where: { $0.imageFile == image.savedFileName }) {
      store.unsave(savedItem)
    } else {
      store.save(image)
    }
  }
}

/// The layout shared by brief images and saved images: a big image with a
/// caption row and a save toggle underneath.
struct DailyBriefEnlargedImageContent: View {
  let url: URL
  let caption: String?
  let detail: String?
  let isSaved: Bool
  let onToggleSave: () -> Void

  @State private var image: CGImage?

  var body: some View {
    VStack(spacing: 16) {
      // Loaded here rather than with DailyBriefFileImage, whose tinted
      // placeholder would fill the whole area around an aspect-fit image.
      ZStack {
        if let image {
          Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 10)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .task(id: url) {
        let fileURL = url
        image = await Task.detached(priority: .userInitiated) {
          DailyBriefFileImage.loadThumbnail(fileURL)
        }.value
      }

      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          if let caption, !caption.isEmpty {
            Text(caption)
              .font(.custom("Figtree", size: 14).weight(.medium))
              .foregroundStyle(.white)
              .lineLimit(2)
          }
          if let detail {
            Text(detail)
              .font(.custom("Figtree", size: 12))
              .foregroundStyle(.white.opacity(0.7))
          }
        }

        Spacer(minLength: 12)

        Button(action: onToggleSave) {
          DailyBriefRoutePill(
            title: isSaved ? "Saved" : "Save",
            systemImage: isSaved ? "bookmark.fill" : "bookmark"
          )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
      }
      .frame(maxWidth: 720)
    }
    .padding(.horizontal, 64)
    .padding(.top, 60)
    .padding(.bottom, 36)
  }
}
