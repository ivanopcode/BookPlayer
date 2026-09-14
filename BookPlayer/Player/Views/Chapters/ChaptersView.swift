//
//  ChaptersView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 7/9/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Kingfisher
import SwiftUI

/// The chapter navigator: a system sheet with the book's header (cover, title, author, extended
/// map), a scrollable list of chapters, and a pinned bottom panel for confirming a jump.
///
/// Tapping a row only selects it for preview — it never changes playback. The confirm button is
/// the single place that issues `jumpToChapter`. Closing without confirming preserves position.
struct ChaptersView: View {
  @StateObject private var model: Self.Model
  @StateObject private var theme = ThemeViewModel()
  @Environment(\.dismiss) private var dismiss
  /// Ensures the "scroll to the current chapter" happens only once on open, so a later manual
  /// scroll is never pulled back automatically.
  @State private var hasPerformedInitialScroll = false

  init(initModel: @escaping () -> Self.Model) {
    self._model = .init(wrappedValue: initModel())
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          Section {
            headerView
              .listRowInsets(EdgeInsets())
              .listRowSeparator(.hidden)
          }
          Section {
            ForEach(Array(model.chapters.enumerated()), id: \.element.id) { index, chapter in
              rowView(chapter, position: index + 1)
                .id(chapter.id)
            }
          }
        }
        .listStyle(.plain)
        .applyListStyle(with: theme, background: theme.systemBackgroundColor)
        .onAppear {
          // On open: the current chapter is pre-selected (see Model.init) and centered once.
          if !hasPerformedInitialScroll, let current = model.currentChapter {
            hasPerformedInitialScroll = true
            withAnimation {
              proxy.scrollTo(current.id, anchor: .center)
            }
          }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          bottomPanel
        }
        .navigationTitle("chapters_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button {
              // Closing without confirming keeps the playback position untouched.
              dismiss()
            } label: {
              Label("voiceover_close_button", systemImage: "xmark")
            }
            .foregroundStyle(theme.linkColor)
            .accessibilityLabel("voiceover_close_button")
          }
          if model.canReloadChapters {
            ToolbarItem(placement: .confirmationAction) {
              reloadButton
            }
          }
        }
        .bpAlert($model.currentAlert)
      }
    }
  }

  // MARK: - Header

  @ViewBuilder
  private var headerView: some View {
    VStack(alignment: .leading, spacing: Spacing.S2) {
      HStack(spacing: Spacing.S1) {
        bookCover
          .frame(width: 52, height: 52)
        VStack(alignment: .leading, spacing: 2) {
          Text(model.bookTitle)
            .bpFont(.title)
            .foregroundStyle(theme.primaryColor)
            .lineLimit(2)
          Text(model.bookAuthor)
            .bpFont(.caption)
            .foregroundStyle(theme.secondaryColor)
            .lineLimit(1)
        }
        Spacer()
      }

      if model.mapLayout.isRenderable {
        ChapterMapBar(
          layout: model.mapLayout,
          barHeight: 16,
          accessibilityLabel: mapAccessibilityLabel
        )
        .padding(.top, Spacing.S2)
      }
    }
    .padding(Spacing.S)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(model.bookTitle), \(model.bookAuthor)")
  }

  @ViewBuilder
  private var bookCover: some View {
    Group {
      if let path = model.bookRelativePath, !path.isEmpty {
        KFImage
          .dataProvider(ArtworkService.getArtworkProvider(for: path))
          .targetCache(ArtworkService.cache)
          .resizable()
          .scaledToFill()
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(theme.secondarySystemFillColor)
          .overlay(
            Image(systemName: "book.closed")
              .foregroundStyle(theme.secondaryColor)
          )
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityHidden(true)
  }

  private var mapAccessibilityLabel: String {
    let chapterPart = model.currentChapter.map { chapter in
      String.localizedStringWithFormat(
        "player_chapter_description".localized,
        chapter.index,
        model.chapters.count
      )
    } ?? ""
    let timePart = String.localizedStringWithFormat(
      "chapter_map_time_label".localized,
      TimeParser.formatTime(model.mapCurrentTime),
      TimeParser.formatTime(model.bookDuration)
    )
    return String.localizedStringWithFormat(
      "chapter_map_accessibility_label".localized,
      chapterPart,
      timePart
    )
  }

  // MARK: - Row

  @ViewBuilder
  private func rowView(_ chapter: PlayableChapter, position: Int) -> some View {
    let isSelected = chapter == model.selectedChapter
    let title = model.displayTitle(chapter: chapter, position: position)
    let subtitle = String.localizedStringWithFormat(
      "chapters_item_description".localized,
      TimeParser.formatTime(chapter.start),
      TimeParser.formatTime(chapter.duration)
    )

    Button {
      // Selecting is a preview only — it never changes playback.
      model.selectChapter(chapter)
    } label: {
      rowContent(
        position: position,
        isSelected: isSelected,
        isCurrent: chapter == model.currentChapter,
        title: title,
        subtitle: subtitle
      )
    }
    .buttonStyle(.plain)
    .listRowBackground(theme.systemBackgroundColor)
    .listRowSeparator(isSelected ? .hidden : .visible)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      [
        String.localizedStringWithFormat("chapter_number_title".localized, position),
        title,
        subtitle
      ].joined(separator: ", ")
    )
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  @ViewBuilder
  private func rowContent(
    position: Int,
    isSelected: Bool,
    isCurrent: Bool,
    title: String,
    subtitle: String
  ) -> some View {
    HStack(spacing: Spacing.S2) {
      Text("\(position)")
        .bpFont(.captionMedium)
        .monospacedDigit()
        .minimumScaleFactor(0.6)
        .frame(width: 28, height: 28)
        .background(Circle().fill(isCurrent ? theme.linkColor : theme.secondarySystemFillColor))
        .foregroundStyle(isCurrent ? theme.systemBackgroundColor : theme.secondaryColor)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .bpFont(.titleRegular)
          .foregroundStyle(theme.primaryColor)
          .multilineTextAlignment(.leading)
        Text(subtitle)
          .bpFont(.caption)
          .foregroundStyle(theme.secondaryColor)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if isSelected {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(theme.linkColor)
      }
    }
    .padding(.vertical, Spacing.S2)
    .padding(.horizontal, Spacing.S2)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(isSelected ? theme.linkColor.opacity(0.12) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(isSelected ? theme.linkColor : Color.clear, lineWidth: 1)
    )
  }

  // MARK: - Bottom panel

  @ViewBuilder
  private var bottomPanel: some View {
    VStack(spacing: Spacing.S2) {
      if let selected = model.selectedChapter {
        let position = (model.chapters.firstIndex(where: { $0 == selected }) ?? 0) + 1
        HStack(alignment: .top, spacing: Spacing.S2) {
          VStack(alignment: .leading, spacing: 2) {
            Text(model.displayTitle(chapter: selected, position: position))
              .bpFont(.title)
              .foregroundStyle(theme.primaryColor)
              .lineLimit(1)
            Text(String.localizedStringWithFormat(
              "chapters_item_description".localized,
              TimeParser.formatTime(selected.start),
              TimeParser.formatTime(selected.duration)
            ))
            .bpFont(.caption)
            .foregroundStyle(theme.secondaryColor)
          }
          Spacer()
        }

        Button {
          // The confirm is the single point that issues the jump; on success we dismiss.
          if model.confirmJump() {
            dismiss()
          }
        } label: {
          Text(model.selectedChapterIsCurrent
            ? "chapter_go_start_title"
            : "chapter_go_title"
          )
          .bpFont(.title)
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
    }
    .padding(Spacing.S)
    .frame(maxWidth: .infinity)
    .background(.ultraThinMaterial)
  }

  @ViewBuilder
  private var reloadButton: some View {
    Button {
      Task { await model.reloadChapters() }
    } label: {
      // Keep the title laid out (just hidden) while loading so the spinner overlay doesn't
      // change the toolbar item's width.
      Text("reload_button")
        .foregroundStyle(theme.linkColor)
        .opacity(model.isReloadingChapters ? 0 : 1)
        .overlay {
          if model.isReloadingChapters {
            ProgressView()
          }
        }
    }
    .disabled(model.isReloadingChapters)
    .accessibilityLabel("reload_chapters_title")
  }
}

#Preview {
  @Previewable var chapter1 = PlayableChapter(
    title: "Chapter 1",
    author: "Author 1",
    start: .zero,
    duration: 300,
    relativePath: "book1.m4b",
    remoteURL: nil,
    index: 0
  )

  ChaptersView {
    .init(
      chapters: [
        chapter1,
        .init(
          title: "Chapter 2",
          author: "Author 1",
          start: 300,
          duration: 300,
          relativePath: "book1.m4b",
          remoteURL: nil,
          index: 1
        ),
      ],
      currentChapter: chapter1,
      bookTitle: "Audiobook",
      bookAuthor: "Author 1",
      bookRelativePath: "book1.m4b",
      bookDuration: 600
    )
  }
}
