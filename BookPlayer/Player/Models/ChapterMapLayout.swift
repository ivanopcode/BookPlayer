//
//  ChapterMapLayout.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Foundation

/// Pure, dependency-free computation of the "book map".
///
/// The model is deliberately independent of SwiftUI and the audio engine. It takes value inputs —
/// chapters in the book's *global* time coordinate, the book's total duration, and the current
/// playback position — and returns normalized `0...1` intervals plus the normalized playhead. It
/// never reorders the input chapters and never mutates them.
///
/// Playback speed intentionally does **not** shape the geometry: the map is a function of real
/// (unscaled) time only, so changing the speed never moves the segments or the marker.
enum ChapterMapLayout {

  /// One normalized chapter segment. `start`/`end` are in `0...1` book space and `end >= start`.
  struct Segment: Equatable {
    /// Position of this segment within the input chapter array. Chapters are never reordered, so
    /// this always matches the caller's array index.
    let chapterPosition: Int
    let start: Double
    let end: Double

    var width: Double { max(0, end - start) }
  }

  /// The computed map for a book.
  struct Layout: Equatable {
    let segments: [Segment]
    /// Normalized playhead position in `0...1` (already clamped).
    let progress: Double

    /// Whether the map is worth rendering: at least two chapters that together form a real
    /// division. A single chapter, or all-zero data, produces no useful segmentation and is
    /// hidden by the caller.
    var isRenderable: Bool {
      segments.count >= 2 && segments.filter { $0.width > 0 }.count >= 2
    }
  }

  // MARK: - Computation

  /// Computes the normalized layout for a book.
  ///
  /// - Parameters:
  ///   - chapters: chapters in the book's global time coordinate, in their natural (source) order.
  ///     For combined (bound) books this is the per-file chapter list whose `start` values are
  ///     cumulative offsets into the whole book, so the segments tile the timeline.
  ///   - totalDuration: the book's total duration in seconds.
  ///   - currentTime: the current playback position in seconds, in the same global coordinate.
  /// - Returns: a `Layout` with one segment per input chapter (in order) and a clamped playhead.
  static func layout(
    chapters: [PlayableChapter],
    totalDuration: TimeInterval,
    currentTime: TimeInterval
  ) -> Layout {
    let total = sanitized(totalDuration)
    guard total > 0 else { return Layout(segments: [], progress: 0) }

    var segments: [Segment] = []
    segments.reserveCapacity(chapters.count)

    for (position, chapter) in chapters.enumerated() {
      let start = sanitized(chapter.start)
      let end = sanitized(chapter.start + chapter.duration)
      segments.append(
        Segment(
          chapterPosition: position,
          start: clamp01(start / total),
          end: clamp01(end / total)
        )
      )
    }

    return Layout(segments: segments, progress: normalized(currentTime, total: total))
  }

  // MARK: - Divider culling

  /// The boundary positions (in `0...1`) at which a thin divider should be drawn, so that a book
  /// with hundreds of chapters does not paint a dense forest of lines.
  ///
  /// A boundary between two adjacent chapters is kept only when *both* chapters are at least
  /// `minimumChapterWidth` points wide at the given `availableWidth`.
  static func visibleDividers(
    segments: [Segment],
    availableWidth: CGFloat,
    minimumChapterWidth: CGFloat = 10
  ) -> [Double] {
    guard segments.count >= 2, availableWidth > 0 else { return [] }

    var result: [Double] = []
    for index in 1..<segments.count {
      let left = segments[index - 1].width * Double(availableWidth)
      let right = segments[index].width * Double(availableWidth)
      if left >= minimumChapterWidth && right >= minimumChapterWidth {
        result.append(segments[index].start)
      }
    }
    return result
  }

  // MARK: - Helpers

  private static func sanitized(_ value: TimeInterval) -> Double {
    value.isFinite ? max(0, value) : 0
  }

  private static func clamp01(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }

  private static func normalized(_ currentTime: TimeInterval, total: Double) -> Double {
    guard currentTime.isFinite, total > 0 else { return 0 }
    return clamp01(currentTime / total)
  }
}
