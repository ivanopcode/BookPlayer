//
//  ChapterMapView.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

/// A compact, proportional "book map" bar.
///
/// The whole book is rendered as a single rounded track whose width is split into segments
/// proportional to each chapter's duration. An accent fill covers the track up to the current
/// position, a marker sits at that position, and thin dividers separate the chapters (culled by
/// `ChapterMapLayout.visibleDividers` so very long books do not become a dense forest of lines).
///
/// The bar is exposed to accessibility as a **single** element described by `accessibilityLabel`.
/// It renders with discrete updates (no implicit animation), so Reduce Motion is respected by
/// construction.
struct ChapterMapBar: View {
  @EnvironmentObject private var theme: ThemeViewModel

  let layout: ChapterMapLayout.Layout
  /// Track height in points. The spec asks for 10–12 pt on the player.
  var barHeight: CGFloat = 11
  /// VoiceOver label describing the map (chapter + position).
  var accessibilityLabel: String

  private var markerDiameter: CGFloat { barHeight + 4 }
  private var totalHeight: CGFloat { markerDiameter }

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      let centerY = geo.size.height / 2
      let dividers = ChapterMapLayout.visibleDividers(
        segments: layout.segments,
        availableWidth: width
      )
      let markerX = width * CGFloat(layout.progress)

      ZStack {
        // Neutral track for the whole book
        Capsule()
          .fill(theme.secondarySystemFillColor)
          .frame(height: barHeight)

        // Accent fill from the start up to the current position
        Capsule()
          .fill(theme.linkColor)
          .frame(height: barHeight)
          .mask {
            Rectangle()
              .frame(width: max(0, width * CGFloat(layout.progress)))
              .frame(maxWidth: .infinity, alignment: .leading)
          }

        // Thin dividers between chapters (only where both neighbours are wide enough)
        ForEach(dividers, id: \.self) { position in
          Rectangle()
            .fill(theme.separatorColor)
            .frame(width: 1, height: barHeight)
            .position(x: width * CGFloat(position), y: centerY)
        }

        // Position marker
        Circle()
          .fill(theme.primaryColor)
          .frame(width: markerDiameter, height: markerDiameter)
          .overlay(Circle().stroke(theme.systemBackgroundColor, lineWidth: 1.5))
          .position(x: markerX, y: centerY)
      }
    }
    .frame(height: totalHeight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }
}

#Preview {
  let chapters = (0..<8).map { i in
    PlayableChapter(
      title: "Chapter \(i + 1)",
      author: "Author",
      start: Double(i) * 60,
      duration: 60,
      relativePath: "book.m4b",
      remoteURL: nil,
      index: Int16(i)
    )
  }
  ChapterMapBar(
    layout: ChapterMapLayout.layout(chapters: chapters, totalDuration: 480, currentTime: 210),
    barHeight: 11,
    accessibilityLabel: "Book map"
  )
  .padding()
  .environmentObject(ThemeViewModel())
}
