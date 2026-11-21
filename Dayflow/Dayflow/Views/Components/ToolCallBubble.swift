//
//  ToolCallBubble.swift
//  Dayflow
//
//  Animated tool call indicator showing when the AI is fetching data.
//  Features a shimmer effect while running and smooth state transitions.
//

import SwiftUI

struct ToolCallBubble: View {
  let message: ChatMessage
  @State private var shimmerOffset: CGFloat = -1.0
  @State private var spinnerRotation: Double = 0
  @State private var appearScale: CGFloat = 0.8
  @State private var appearOpacity: Double = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dayflowTheme) private var theme

  private var isDark: Bool { theme.isDark }

  var body: some View {
    HStack(spacing: 8) {
      statusIcon
      statusText
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(backgroundView)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(borderOverlay)
    .shadow(color: shadowColor, radius: 6, x: 0, y: 3)
    .scaleEffect(appearScale)
    .opacity(appearOpacity)
    .onAppear {
      withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
        appearScale = 1.0
        appearOpacity = 1.0
      }
      startAnimationsIfNeeded()
    }
    .onChange(of: message.toolStatus) {
      // Subtle bounce when status changes
      withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
        appearScale = 1.03
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
          appearScale = 1.0
        }
      }
    }
  }

  // MARK: - Status Icon

  @ViewBuilder
  private var statusIcon: some View {
    switch message.toolStatus {
    case .running:
      // Animated spinner
      Image(systemName: "circle.dotted")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(Color(hex: "F96E00"))
        .rotationEffect(.degrees(spinnerRotation))

    case .completed:
      // Green checkmark
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(Color(hex: "34C759"))

    case .failed:
      // Red X
      Image(systemName: "xmark.circle.fill")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(Color(hex: "FF3B30"))

    case nil:
      EmptyView()
    }
  }

  // MARK: - Status Text

  @ViewBuilder
  private var statusText: some View {
    switch message.toolStatus {
    case .running:
      Text(message.content)
        .font(.custom("Figtree", size: 12).weight(.semibold))
        .foregroundColor(runningTextColor)

    case .completed(let summary):
      Text(summary)
        .font(.custom("Figtree", size: 12).weight(.semibold))
        .foregroundColor(completedTextColor)

    case .failed(let error):
      Text(error)
        .font(.custom("Figtree", size: 12).weight(.semibold))
        .foregroundColor(failedTextColor)

    case nil:
      Text(message.content)
        .font(.custom("Figtree", size: 12).weight(.semibold))
        .foregroundColor(runningTextColor)
    }
  }

  // Dark mode lifts the status text colors so they keep their contrast on
  // the tinted dark fills; light keeps the Figma values exactly.
  private var runningTextColor: Color {
    isDark ? Color(hex: "E2A079") : Color(hex: "8B5E3C")
  }

  private var completedTextColor: Color {
    isDark ? Color(hex: "5ED4AC") : Color(hex: "2D7D46")
  }

  private var failedTextColor: Color {
    isDark ? Color(hex: "FF8A80") : Color(hex: "C62828")
  }

  // MARK: - Background

  @ViewBuilder
  private var backgroundView: some View {
    switch message.toolStatus {
    case .running:
      ZStack {
        // Base gradient
        LinearGradient(
          colors: runningBackgroundColors,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        // Shimmer overlay
        if !reduceMotion {
          ShimmerOverlay(offset: shimmerOffset, highlightOpacity: isDark ? 0.25 : 0.5)
            .blendMode(.softLight)
        }
      }

    case .completed:
      LinearGradient(
        colors: completedBackgroundColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

    case .failed:
      LinearGradient(
        colors: failedBackgroundColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

    case nil:
      nilBackgroundColor
    }
  }

  // Light keeps the soft pastel fills; dark re-tints each status hue at low
  // alpha over the dark canvas, the same treatment the weekly palette uses.
  private var runningBackgroundColors: [Color] {
    isDark
      ? [Color(hex: "F96E00").opacity(0.16), Color(hex: "F96E00").opacity(0.22)]
      : [Color(hex: "FFF4E9"), Color(hex: "FFECD8")]
  }

  private var completedBackgroundColors: [Color] {
    isDark
      ? [Color(hex: "34C759").opacity(0.12), Color(hex: "34C759").opacity(0.18)]
      : [Color(hex: "E8F5E9"), Color(hex: "C8E6C9")]
  }

  private var failedBackgroundColors: [Color] {
    isDark
      ? [Color(hex: "FF3B30").opacity(0.12), Color(hex: "FF3B30").opacity(0.18)]
      : [Color(hex: "FFEBEE"), Color(hex: "FFCDD2")]
  }

  private var nilBackgroundColor: Color {
    isDark ? Color(hex: "F96E00").opacity(0.16) : Color(hex: "FFF4E9")
  }

  // MARK: - Border

  private var borderOverlay: some View {
    RoundedRectangle(cornerRadius: 16, style: .continuous)
      .strokeBorder(borderColor, lineWidth: 1.5)
  }

  private var borderColor: Color {
    let opacity = isDark ? 0.5 : 0.3
    switch message.toolStatus {
    case .running:
      return Color(hex: "F96E00").opacity(opacity)
    case .completed:
      return Color(hex: "34C759").opacity(opacity)
    case .failed:
      return Color(hex: "FF3B30").opacity(opacity)
    case nil:
      return Color(hex: "F96E00").opacity(opacity)
    }
  }

  private var shadowColor: Color {
    if isDark { return .black.opacity(0.3) }
    switch message.toolStatus {
    case .running:
      return Color(hex: "F96E00").opacity(0.1)
    case .completed:
      return Color(hex: "34C759").opacity(0.1)
    case .failed:
      return Color(hex: "FF3B30").opacity(0.1)
    case nil:
      return Color(hex: "F96E00").opacity(0.1)
    }
  }

  // MARK: - Animations

  private func startAnimationsIfNeeded() {
    guard message.isRunning, !reduceMotion else { return }

    // Continuous spinner rotation
    withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
      spinnerRotation = 360
    }

    // Continuous shimmer animation
    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
      shimmerOffset = 1.0
    }
  }
}

// MARK: - Shimmer Overlay

private struct ShimmerOverlay: View {
  let offset: CGFloat
  var highlightOpacity: Double = 0.5

  var body: some View {
    GeometryReader { geo in
      LinearGradient(
        colors: [
          Color.white.opacity(0),
          Color.white.opacity(highlightOpacity),
          Color.white.opacity(0),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(width: geo.size.width * 0.4)
      .offset(x: offset * geo.size.width * 1.4 - geo.size.width * 0.2)
    }
    .clipped()
  }
}

// MARK: - Preview

#Preview("Tool Call Bubble - Running") {
  VStack(spacing: 20) {
    ToolCallBubble(
      message: ChatMessage(
        role: .toolCall,
        content: String(localized: "Fetching Tuesday's timeline..."),
        toolStatus: .running
      )
    )

    ToolCallBubble(
      message: ChatMessage(
        role: .toolCall,
        content: String(localized: "Fetching timeline..."),
        toolStatus: .completed(summary: String(localized: "Found 8 activities for Jan 7th"))
      )
    )

    ToolCallBubble(
      message: ChatMessage(
        role: .toolCall,
        content: String(localized: "Fetching timeline..."),
        toolStatus: .failed(error: String(localized: "No data found for this date"))
      )
    )
  }
  .padding(40)
  .background(Color(hex: "FAF5F0"))
}
