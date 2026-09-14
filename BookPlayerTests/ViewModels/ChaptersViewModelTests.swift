//
//  ChaptersViewModelTests.swift
//  BookPlayerTests
//
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

@testable import BookPlayer
@testable import BookPlayerKit
import Combine
import XCTest

@MainActor
final class ChaptersViewModelTests: XCTestCase {
  private var playerManagerMock: PlayerManagerProtocolMock!
  private var libraryServiceMock: LibraryServiceProtocolMock!

  override func setUp() {
    super.setUp()
    DataTestUtils.clearFolderContents(url: DataManager.getProcessedFolderURL())
    playerManagerMock = PlayerManagerProtocolMock()
    libraryServiceMock = LibraryServiceProtocolMock()
    // The view model subscribes to `currentItemPublisher()`; give the mock a valid (empty) stream.
    playerManagerMock.currentItemPublisherReturnValue =
      Empty<PlayableItem?, Never>(completeImmediately: true).eraseToAnyPublisher()
  }

  private func makeItem(relativePath: String, isBoundBook: Bool, chapterCount: Int = 1) -> PlayableItem {
    let chapters = (0..<chapterCount).map { index in
      PlayableChapter(
        title: "chapter \(index + 1)",
        author: "author",
        start: Double(index) * 10,
        duration: 10,
        relativePath: relativePath,
        remoteURL: nil,
        index: Int16(index)
      )
    }
    return makeItem(relativePath: relativePath, isBoundBook: isBoundBook, chapters: chapters)
  }

  private func makeItem(relativePath: String, isBoundBook: Bool, chapters: [PlayableChapter]) -> PlayableItem {
    PlayableItem(
      title: "title",
      author: "author",
      chapters: chapters,
      currentTime: 0,
      duration: 100,
      relativePath: relativePath,
      uuid: "uuid",
      parentFolder: nil,
      percentCompleted: 0,
      lastPlayDate: nil,
      isFinished: false,
      isBoundBook: isBoundBook
    )
  }

  private func makeChapter(start: Double, duration: Double, index: Int16, relativePath: String) -> PlayableChapter {
    PlayableChapter(
      title: "chapter \(index)",
      author: "author",
      start: start,
      duration: duration,
      relativePath: relativePath,
      remoteURL: nil,
      index: index
    )
  }

  private func makeSUT() -> ChaptersViewModel {
    ChaptersViewModel(playerManager: playerManagerMock, libraryService: libraryServiceMock)
  }

  private func createLocalFile(named name: String) {
    _ = DataTestUtils.generateTestFile(
      name: name,
      contents: Data("stub".utf8),
      destinationFolder: DataManager.getProcessedFolderURL()
    )
  }

  func testCanReloadChapters_singleFileBook_isTrue() {
    playerManagerMock.currentItem = makeItem(relativePath: "book.m4b", isBoundBook: false)
    XCTAssertTrue(makeSUT().canReloadChapters)
  }

  func testCanReloadChapters_boundBook_isFalse() {
    playerManagerMock.currentItem = makeItem(relativePath: "folder", isBoundBook: true)
    XCTAssertFalse(makeSUT().canReloadChapters)
  }

  func testReloadChapters_whenMoreFound_reloadsItemAndRefreshesList() async {
    createLocalFile(named: "reparse.m4b")
    playerManagerMock.currentItem = makeItem(relativePath: "reparse.m4b", isBoundBook: false, chapterCount: 1)
    libraryServiceMock.reloadChaptersRelativePathReturnValue = 5
    // Simulate PlayerManager rebuilding currentItem from storage with the new chapter count.
    let reloadedItem = makeItem(relativePath: "reparse.m4b", isBoundBook: false, chapterCount: 5)
    playerManagerMock.reloadCurrentItemClosure = { [weak self] in
      self?.playerManagerMock.currentItem = reloadedItem
    }
    let sut = makeSUT()

    await sut.reloadChapters()

    XCTAssertTrue(libraryServiceMock.reloadChaptersRelativePathCalled)
    XCTAssertTrue(playerManagerMock.reloadCurrentItemCalled)
    XCTAssertEqual(sut.chapters.count, 5)
    XCTAssertNotNil(sut.currentAlert)
    XCTAssertFalse(sut.isReloadingChapters)
  }

  func testReloadChapters_whenFileNotDownloaded_alertsWithoutParsing() async {
    // No file created on disk for this relativePath.
    playerManagerMock.currentItem = makeItem(relativePath: "missing.m4b", isBoundBook: false)
    let sut = makeSUT()

    await sut.reloadChapters()

    XCTAssertFalse(libraryServiceMock.reloadChaptersRelativePathCalled)
    XCTAssertFalse(playerManagerMock.reloadCurrentItemCalled)
    XCTAssertNotNil(sut.currentAlert)
    XCTAssertFalse(sut.isReloadingChapters)
  }

  func testReloadChapters_whenNoAdditionalFound_alertsAndDoesNotReloadItem() async {
    createLocalFile(named: "none.m4b")
    playerManagerMock.currentItem = makeItem(relativePath: "none.m4b", isBoundBook: false)
    libraryServiceMock.reloadChaptersRelativePathReturnValue = nil
    let sut = makeSUT()

    await sut.reloadChapters()

    XCTAssertTrue(libraryServiceMock.reloadChaptersRelativePathCalled)
    XCTAssertFalse(playerManagerMock.reloadCurrentItemCalled)
    XCTAssertNotNil(sut.currentAlert)
    XCTAssertFalse(sut.isReloadingChapters)
  }

  func testReloadChapters_boundBook_isNoOp() async {
    playerManagerMock.currentItem = makeItem(relativePath: "folder", isBoundBook: true)
    let sut = makeSUT()

    await sut.reloadChapters()

    XCTAssertFalse(libraryServiceMock.reloadChaptersRelativePathCalled)
    XCTAssertNil(sut.currentAlert)
  }

  // MARK: - Preview selection (no playback change)

  func testSelectingChapterOnlyPreviewsWithoutJumping() {
    let item = makeItem(relativePath: "book.m4b", isBoundBook: false, chapterCount: 3)
    playerManagerMock.currentItem = item
    let sut = makeSUT()

    let target = item.chapters[2]
    sut.selectChapter(target)

    XCTAssertEqual(sut.selectedChapter, target)
    // Preview selection must not change playback.
    XCTAssertFalse(playerManagerMock.jumpToChapterCalled)
    XCTAssertFalse(playerManagerMock.jumpToRecordBookmarkCalled)
    XCTAssertFalse(playerManagerMock.playCalled)
  }

  func testInitialSelectionIsTheCurrentChapter() {
    let item = makeItem(relativePath: "book.m4b", isBoundBook: false, chapterCount: 3)
    playerManagerMock.currentItem = item
    let sut = makeSUT()

    XCTAssertEqual(sut.selectedChapter, item.currentChapter)
  }

  // MARK: - One-time confirm

  func testConfirmJumpCallsJumpToChapterExactlyOnce() {
    let item = makeItem(relativePath: "book.m4b", isBoundBook: false, chapterCount: 3)
    playerManagerMock.currentItem = item
    let sut = makeSUT()

    let target = item.chapters[1]
    sut.selectChapter(target)

    let first = sut.confirmJump()
    let second = sut.confirmJump()

    XCTAssertTrue(first)
    XCTAssertFalse(second)
    XCTAssertEqual(playerManagerMock.jumpToChapterCallsCount, 1)
    XCTAssertEqual(playerManagerMock.jumpToChapterReceivedChapter, target)
    // Confirming must not start playback on its own.
    XCTAssertFalse(playerManagerMock.playCalled)
    XCTAssertFalse(playerManagerMock.playPauseCalled)
  }

  func testConfirmJumpWithoutSelectionDoesNothing() {
    let item = makeItem(relativePath: "book.m4b", isBoundBook: false, chapterCount: 1)
    playerManagerMock.currentItem = item
    let sut = makeSUT()

    sut.selectedChapter = nil

    let result = sut.confirmJump()

    XCTAssertFalse(result)
    XCTAssertFalse(playerManagerMock.jumpToChapterCalled)
  }

  // MARK: - Reset on book change

  func testApplyItemResetsSelectionWhenBookChanges() {
    let firstBook = makeItem(relativePath: "bookA.m4b", isBoundBook: false, chapterCount: 3)
    playerManagerMock.currentItem = firstBook
    let sut = makeSUT()

    sut.selectChapter(firstBook.chapters[1])
    XCTAssertEqual(sut.selectedChapter, firstBook.chapters[1])

    let secondBook = makeItem(relativePath: "bookB.m4b", isBoundBook: false, chapterCount: 2)
    sut.applyItem(secondBook)

    XCTAssertEqual(sut.bookRelativePath, "bookB.m4b")
    XCTAssertEqual(sut.chapters, secondBook.chapters)
    // The selection resets to the new book's current chapter, not the old book's chapter.
    XCTAssertEqual(sut.selectedChapter, secondBook.currentChapter)
    XCTAssertNotEqual(sut.selectedChapter, firstBook.chapters[1])
  }

  // MARK: - Reset vanished selection after a refresh

  func testApplyItemResetsVanishedSelectionAfterRefresh() {
    let original = makeItem(relativePath: "book.m4b", isBoundBook: false, chapterCount: 3)
    playerManagerMock.currentItem = original
    let sut = makeSUT()

    sut.selectChapter(original.chapters[1])
    XCTAssertEqual(sut.selectedChapter, original.chapters[1])

    // A refresh with a different split: the selected chapter no longer exists.
    let refreshed = makeItem(
      relativePath: "book.m4b",
      isBoundBook: false,
      chapters: [
        makeChapter(start: 0, duration: 20, index: 0, relativePath: "book.m4b"),
        makeChapter(start: 20, duration: 20, index: 1, relativePath: "book.m4b"),
        makeChapter(start: 40, duration: 20, index: 2, relativePath: "book.m4b"),
      ]
    )
    sut.applyItem(refreshed)

    XCTAssertFalse(refreshed.chapters.contains { $0 == original.chapters[1] })
    // Falls back to the refreshed book's current chapter.
    XCTAssertEqual(sut.selectedChapter, refreshed.currentChapter)
  }

  // MARK: - Map data

  func testMapLayoutReflectsBookAndPosition() {
    let item = makeItem(relativePath: "book.m4b", isBoundBook: false, chapterCount: 4)
    playerManagerMock.currentItem = item
    let sut = makeSUT()

    sut.mapCurrentTime = 50 // halfway through the 100s book

    let layout = sut.mapLayout
    XCTAssertEqual(layout.segments.count, 4)
    XCTAssertEqual(layout.progress, 0.5, accuracy: 1e-9)
    XCTAssertTrue(layout.isRenderable)
  }
}
