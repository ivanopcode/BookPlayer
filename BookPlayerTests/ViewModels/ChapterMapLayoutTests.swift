//
//  ChapterMapLayoutTests.swift
//  BookPlayerTests
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation
import XCTest

@testable import BookPlayer

final class ChapterMapLayoutTests: XCTestCase {
  private func chapter(
    start: TimeInterval,
    duration: TimeInterval,
    index: Int16 = 0,
    title: String = "chapter"
  ) -> PlayableChapter {
    PlayableChapter(
      title: title,
      author: "author",
      start: start,
      duration: duration,
      relativePath: "book.m4b",
      remoteURL: nil,
      index: index
    )
  }

  // MARK: - Proportions & boundaries

  func testSegmentsAreProportionalToDurationAndPreserveOrder() {
    let layout = ChapterMapLayout.layout(
      chapters: [
        chapter(start: 0, duration: 60, index: 0),
        chapter(start: 60, duration: 120, index: 1),
        chapter(start: 180, duration: 60, index: 2),
      ],
      totalDuration: 240,
      currentTime: 0
    )

    XCTAssertEqual(layout.segments.count, 3)
    // Widths are proportional to duration.
    XCTAssertEqual(layout.segments[0].width, 60 / 240, accuracy: 1e-9)
    XCTAssertEqual(layout.segments[1].width, 120 / 240, accuracy: 1e-9)
    XCTAssertEqual(layout.segments[2].width, 60 / 240, accuracy: 1e-9)

    // Boundaries line up exactly at the chapter edges.
    XCTAssertEqual(layout.segments[0].start, 0, accuracy: 1e-9)
    XCTAssertEqual(layout.segments[0].end, 0.25, accuracy: 1e-9)
    XCTAssertEqual(layout.segments[1].start, 0.25, accuracy: 1e-9)
    XCTAssertEqual(layout.segments[1].end, 0.75, accuracy: 1e-9)
    XCTAssertEqual(layout.segments[2].start, 0.75, accuracy: 1e-9)
    XCTAssertEqual(layout.segments[2].end, 1.0, accuracy: 1e-9)

    // Chapters are never reordered.
    XCTAssertEqual(layout.segments.map(\.chapterPosition), [0, 1, 2])

    // The segments tile the whole book.
    let totalWidth = layout.segments.reduce(0) { $0 + $1.width }
    XCTAssertEqual(totalWidth, 1.0, accuracy: 1e-9)
  }

  func testInputOrderIsPreservedEvenWhenStartsAreOutOfSequence() {
    // Deliberately passed out of time order: the model must keep the caller's order.
    let layout = ChapterMapLayout.layout(
      chapters: [
        chapter(start: 100, duration: 50, index: 1),
        chapter(start: 0, duration: 100, index: 0),
      ],
      totalDuration: 150,
      currentTime: 0
    )

    XCTAssertEqual(layout.segments.count, 2)
    XCTAssertEqual(layout.segments[0].chapterPosition, 0)
    XCTAssertEqual(layout.segments[1].chapterPosition, 1)
  }

  // MARK: - Position

  func testProgressAtStart() {
    let layout = ChapterMapLayout.layout(
      chapters: [chapter(start: 0, duration: 100)],
      totalDuration: 100,
      currentTime: 0
    )
    XCTAssertEqual(layout.progress, 0, accuracy: 1e-9)
  }

  func testProgressAtEnd() {
    let layout = ChapterMapLayout.layout(
      chapters: [chapter(start: 0, duration: 100)],
      totalDuration: 100,
      currentTime: 100
    )
    XCTAssertEqual(layout.progress, 1, accuracy: 1e-9)
  }

  func testProgressIsClampedWhenPositionIsOutOfRange() {
    let chapters = [chapter(start: 0, duration: 50, index: 0), chapter(start: 50, duration: 50, index: 1)]

    let before = ChapterMapLayout.layout(chapters: chapters, totalDuration: 100, currentTime: -50)
    XCTAssertEqual(before.progress, 0, accuracy: 1e-9)

    let after = ChapterMapLayout.layout(chapters: chapters, totalDuration: 100, currentTime: 250)
    XCTAssertEqual(after.progress, 1, accuracy: 1e-9)
  }

  // MARK: - Empty & zero data

  func testEmptyChaptersAreNotRenderable() {
    let layout = ChapterMapLayout.layout(chapters: [], totalDuration: 100, currentTime: 10)
    XCTAssertTrue(layout.segments.isEmpty)
    XCTAssertFalse(layout.isRenderable)
  }

  func testZeroTotalDurationIsNotRenderable() {
    let layout = ChapterMapLayout.layout(
      chapters: [chapter(start: 0, duration: 0), chapter(start: 0, duration: 0)],
      totalDuration: 0,
      currentTime: 0
    )
    XCTAssertTrue(layout.segments.isEmpty)
    XCTAssertFalse(layout.isRenderable)
    XCTAssertEqual(layout.progress, 0)
  }

  func testSingleChapterIsNotRenderable() {
    let layout = ChapterMapLayout.layout(
      chapters: [chapter(start: 0, duration: 100)],
      totalDuration: 100,
      currentTime: 50
    )
    XCTAssertEqual(layout.segments.count, 1)
    XCTAssertFalse(layout.isRenderable)
  }

  func testAllZeroDurationsAreNotRenderable() {
    let layout = ChapterMapLayout.layout(
      chapters: [chapter(start: 0, duration: 0, index: 0), chapter(start: 0, duration: 0, index: 1)],
      totalDuration: 100,
      currentTime: 0
    )
    // Segments exist but have no width, so there is no useful division.
    XCTAssertEqual(layout.segments.count, 2)
    XCTAssertFalse(layout.isRenderable)
  }

  // MARK: - Many chapters

  func testHundredsOfChaptersProduceOneSegmentEach() {
    let count = 500
    let chapters = (0..<count).map { index in
      chapter(start: Double(index), duration: 1, index: Int16(index))
    }
    let layout = ChapterMapLayout.layout(chapters: chapters, totalDuration: Double(count), currentTime: 0)

    XCTAssertEqual(layout.segments.count, count)
    XCTAssertTrue(layout.isRenderable)
    XCTAssertEqual(layout.segments[0].width, 1 / Double(count), accuracy: 1e-9)
    XCTAssertEqual(layout.segments.map(\.chapterPosition), Array(0..<count))
  }

  func testDividerCullingHidesDenseDividersForHundredsOfChapters() {
    let count = 500
    let chapters = (0..<count).map { index in
      chapter(start: Double(index), duration: 1, index: Int16(index))
    }
    let layout = ChapterMapLayout.layout(chapters: chapters, totalDuration: Double(count), currentTime: 0)

    // At a typical width each chapter is ~0.7 pt — far below the minimum, so no dividers.
    let dividers = ChapterMapLayout.visibleDividers(segments: layout.segments, availableWidth: 350)
    XCTAssertTrue(dividers.isEmpty)
  }

  func testDividerCullingKeepsDividersForWideChapters() {
    let layout = ChapterMapLayout.layout(
      chapters: (0..<4).map { index in
        chapter(start: Double(index) * 25, duration: 25, index: Int16(index))
      },
      totalDuration: 100,
      currentTime: 0
    )

    // Each chapter is 87.5 pt wide at 350 pt — above the minimum, so 3 dividers (between 4).
    let dividers = ChapterMapLayout.visibleDividers(segments: layout.segments, availableWidth: 350)
    XCTAssertEqual(dividers.count, 3)
    XCTAssertEqual(dividers, [0.25, 0.5, 0.75])
  }

  // MARK: - Combined (bound) book

  func testCombinedBookUsesGlobalTimeCoordinate() {
    // Three files whose `start` values are cumulative offsets into the whole book.
    let layout = ChapterMapLayout.layout(
      chapters: [
        chapter(start: 0, duration: 100, index: 0),
        chapter(start: 100, duration: 200, index: 1),
        chapter(start: 300, duration: 100, index: 2),
      ],
      totalDuration: 400,
      currentTime: 250
    )

    XCTAssertEqual(layout.segments.map(\.start), [0, 0.25, 0.75])
    XCTAssertEqual(layout.segments.map(\.end), [0.25, 0.75, 1.0])
    // 250s into a 400s book.
    XCTAssertEqual(layout.progress, 0.625, accuracy: 1e-9)
    XCTAssertTrue(layout.isRenderable)
  }

  // MARK: - Playback speed does not change geometry

  func testGeometryIsIndependentOfPlaybackSpeed() {
    let chapters = [
      chapter(start: 0, duration: 60, index: 0),
      chapter(start: 60, duration: 120, index: 1),
    ]
    // The model takes real (unscaled) time only, so the layout is a pure function of the inputs.
    let atOneX = ChapterMapLayout.layout(chapters: chapters, totalDuration: 180, currentTime: 90)
    let again = ChapterMapLayout.layout(chapters: chapters, totalDuration: 180, currentTime: 90)

    XCTAssertEqual(atOneX, again)
    // Halfway through in real time — regardless of the playback speed.
    XCTAssertEqual(atOneX.progress, 0.5, accuracy: 1e-9)
  }

  // MARK: - Bad boundaries

  func testNegativeStartIsClampedIntoTheBook() {
    let layout = ChapterMapLayout.layout(
      chapters: [chapter(start: -50, duration: 100, index: 0), chapter(start: 50, duration: 50, index: 1)],
      totalDuration: 100,
      currentTime: 0
    )
    // The first chapter spans -50...50, clamped to 0...50 → [0, 0.5].
    XCTAssertEqual(layout.segments[0].start, 0, accuracy: 1e-9)
    XCTAssertEqual(layout.segments[0].end, 0.5, accuracy: 1e-9)
  }

  func testChapterBeyondTotalCollapsesToAPoint() {
    let layout = ChapterMapLayout.layout(
      chapters: [chapter(start: 0, duration: 100, index: 0), chapter(start: 200, duration: 50, index: 1)],
      totalDuration: 100,
      currentTime: 0
    )
    XCTAssertEqual(layout.segments[1].start, 1, accuracy: 1e-9)
    XCTAssertEqual(layout.segments[1].end, 1, accuracy: 1e-9)
    XCTAssertEqual(layout.segments[1].width, 0, accuracy: 1e-9)
  }

  func testNonFiniteAndNegativeValuesDoNotCrash() {
    let layout = ChapterMapLayout.layout(
      chapters: [
        chapter(start: .nan, duration: .nan, index: 0),
        chapter(start: .infinity, duration: -100, index: 1),
      ],
      totalDuration: 100,
      currentTime: .nan
    )

    // NaN/Infinity inputs sanitize to finite, in-range values without crashing.
    for segment in layout.segments {
      XCTAssertTrue(segment.start.isFinite)
      XCTAssertTrue(segment.end.isFinite)
      XCTAssertGreaterThanOrEqual(segment.start, 0)
      XCTAssertLessThanOrEqual(segment.start, 1)
    }
    XCTAssertEqual(layout.progress, 0, accuracy: 1e-9)
  }
}
