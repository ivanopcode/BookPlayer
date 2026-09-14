//
//  ChaptersViewModel.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 30/8/21.
//  Copyright © 2021 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Combine
import Foundation

extension ChaptersView {
  @MainActor
  class Model: ObservableObject {
    @Published var chapters: [PlayableChapter]
    @Published var currentChapter: PlayableChapter?
    /// The chapter selected for preview. Selecting never changes playback.
    @Published var selectedChapter: PlayableChapter?
    @Published var isReloadingChapters = false
    @Published var currentAlert: BPAlertContent?
    /// The book position (seconds) used to place the map marker. The concrete view model keeps
    /// this in sync with playback; the base default is the current chapter's start.
    @Published var mapCurrentTime: TimeInterval

    @Published var bookTitle: String
    @Published var bookAuthor: String
    @Published var bookRelativePath: String?
    @Published var bookDuration: TimeInterval

    init(
      chapters: [PlayableChapter],
      currentChapter: PlayableChapter?,
      bookTitle: String,
      bookAuthor: String,
      bookRelativePath: String?,
      bookDuration: TimeInterval
    ) {
      self.chapters = chapters
      self.currentChapter = currentChapter
      // Pre-select the current chapter on open, so the navigator shows it selected + scrolled to.
      self.selectedChapter = currentChapter
      self.mapCurrentTime = currentChapter?.start ?? 0
      self.bookTitle = bookTitle
      self.bookAuthor = bookAuthor
      self.bookRelativePath = bookRelativePath
      self.bookDuration = bookDuration
    }

    /// The chapter map for the header, recomputed from the current chapters and position.
    var mapLayout: ChapterMapLayout.Layout {
      ChapterMapLayout.layout(
        chapters: chapters,
        totalDuration: bookDuration,
        currentTime: mapCurrentTime
      )
    }

    /// The displayed title for a chapter, falling back to "Chapter N" (1-based `position`)
    /// for empty names.
    func displayTitle(chapter: PlayableChapter, position: Int) -> String {
      chapter.title.isEmpty
        ? String.localizedStringWithFormat("chapter_number_title".localized, position)
        : chapter.title
    }

    /// Whether the selected chapter is the currently playing one (drives the confirm label).
    var selectedChapterIsCurrent: Bool {
      guard let selected = selectedChapter else { return false }
      return selected == currentChapter
    }

    /// Selects a chapter for preview only. This never changes playback.
    func selectChapter(_ chapter: PlayableChapter) {
      selectedChapter = chapter
    }

    /// Confirms the jump to the selected chapter. Returns `true` when a jump was issued, so the
    /// caller can dismiss. The base implementation never jumps; the concrete view model performs
    /// the single `jumpToChapter` call.
    @discardableResult
    func confirmJump() -> Bool {
      false
    }

    /// Whether the "re-parse chapters" action applies to the current item.
    var canReloadChapters: Bool { false }

    /// Re-parse chapters from the file, replacing the list when more are found, and surface
    /// the outcome via `currentAlert`.
    func reloadChapters() async {}
  }
}

final class ChaptersViewModel: ChaptersView.Model {
  private let playerManager: PlayerManagerProtocol
  private let libraryService: LibraryServiceProtocol
  /// Guards the confirm action so `jumpToChapter` fires exactly once per presentation.
  private var hasConfirmedJump = false
  private var disposeBag = Set<AnyCancellable>()

  init(playerManager: PlayerManagerProtocol, libraryService: LibraryServiceProtocol) {
    let item = playerManager.currentItem
    self.playerManager = playerManager
    self.libraryService = libraryService
    super.init(
      chapters: item?.chapters ?? [],
      currentChapter: item?.currentChapter,
      bookTitle: item?.title ?? "voiceover_unknown_title".localized,
      bookAuthor: item?.author ?? "voiceover_unknown_title".localized,
      bookRelativePath: item?.relativePath,
      bookDuration: item?.duration ?? 0
    )
    self.mapCurrentTime = item?.currentTime ?? 0
    bindObservers()
  }

  private func bindObservers() {
    // Keep the map marker + current chapter in sync with playback. These are existing
    // notifications posted by the player on every tick and on skips/jumps — no new timer.
    Publishers.Merge(
      NotificationCenter.default.publisher(for: .bookPlaying),
      NotificationCenter.default.publisher(for: .listeningProgressChanged)
    )
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
      self?.syncFromPlayer()
    }
    .store(in: &disposeBag)

    NotificationCenter.default
      .publisher(for: .chapterChange)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.syncFromPlayer()
      }
      .store(in: &disposeBag)

    // A book change (or a reload) rebuilds the navigator from the new item.
    playerManager
      .currentItemPublisher()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] item in
        self?.applyItem(item)
      }
      .store(in: &disposeBag)
  }

  /// Live-syncs the map position and current chapter without touching the preview selection.
  private func syncFromPlayer() {
    let item = playerManager.currentItem
    mapCurrentTime = item?.currentTime ?? 0
    currentChapter = item?.currentChapter
  }

  /// Rebuilds the navigator from a new item, resetting the selection when the book changes or
  /// when a previously selected chapter no longer exists (e.g. after re-parsing).
  func applyItem(_ item: PlayableItem?) {
    guard let item else {
      chapters = []
      currentChapter = nil
      selectedChapter = nil
      mapCurrentTime = 0
      return
    }

    let changedBook = item.relativePath != bookRelativePath

    bookTitle = item.title
    bookAuthor = item.author
    bookRelativePath = item.relativePath
    bookDuration = item.duration
    chapters = item.chapters
    currentChapter = item.currentChapter
    mapCurrentTime = item.currentTime

    if changedBook {
      // A different book: reset the preview selection to the new book's current chapter.
      hasConfirmedJump = false
      selectedChapter = item.currentChapter
    } else if let selected = selectedChapter,
              !item.chapters.contains(where: { $0 == selected }) {
      // The selected chapter vanished after a refresh: fall back to the current chapter.
      selectedChapter = item.currentChapter
    }
  }

  @discardableResult
  override func confirmJump() -> Bool {
    guard let chapter = selectedChapter, !hasConfirmedJump else { return false }
    hasConfirmedJump = true
    // `jumpToChapter` seeks to the chapter start and preserves the play/pause state — it does
    // not start playback on its own.
    playerManager.jumpToChapter(chapter)
    return true
  }

  /// Re-parsing only applies to single-file books; bound books and folders derive their
  /// chapters from constituent files, so there's no embedded chapter track to re-read.
  override var canReloadChapters: Bool {
    playerManager.currentItem?.isBoundBook == false
  }

  @MainActor
  override func reloadChapters() async {
    guard let currentItem = playerManager.currentItem, currentItem.isBoundBook == false else {
      return
    }

    let relativePath = currentItem.relativePath
    let fileURL = DataManager.getProcessedFolderURL().appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      // The file must be downloaded first, through the usual library download flow.
      currentAlert = Self.infoAlert(message: "reparse_chapters_download_description".localized)
      return
    }

    isReloadingChapters = true
    defer { isReloadingChapters = false }

    guard let newCount = await libraryService.reloadChapters(relativePath: relativePath) else {
      currentAlert = Self.infoAlert(message: "reparse_chapters_none_description".localized)
      return
    }

    // Rebuild the player's item so the new chapters take effect everywhere (scrubber, now
    // playing, end-of-chapter sleep timer), then refresh this screen from it — recomputing the
    // map and resetting any selection that no longer exists.
    playerManager.reloadCurrentItem()
    applyItem(playerManager.currentItem)

    currentAlert = Self.infoAlert(
      title: "reparse_chapters_found_title".localized,
      message: String.localizedStringWithFormat("reparse_chapters_found_description".localized, newCount)
    )
  }

  private static func infoAlert(title: String? = nil, message: String) -> BPAlertContent {
    BPAlertContent(title: title, message: message, style: .alert, actionItems: [.okAction])
  }
}
