import SwiftUI

/// Cached DateFormatter for day change detection - creating DateFormatters is expensive (ICU initialization)
private let cachedDayFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter
}()

private let dailyGoalPromptHandledDayKey = "dayGoalPromptHandledTimelineDay"

extension MainView {
  func startDayChangeTimer() {
    stopDayChangeTimer()
    dayChangeTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
      handleMinuteTickForDayChange()
    }
  }

  func stopDayChangeTimer() {
    dayChangeTimer?.invalidate()
    dayChangeTimer = nil
  }

  func handleMinuteTickForDayChange() {
    // Detect timeline day rollover (4am boundary) regardless of what day user is viewing
    let currentTimelineDay = cachedDayFormatter.string(from: timelineDisplayDate(from: Date()))
    if currentTimelineDay != lastObservedTimelineDay {
      lastObservedTimelineDay = currentTimelineDay

      // Jump to current timeline day and re-scroll near now
      setSelectedDate(timelineDisplayDate(from: Date()))
      selectedActivity = nil
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        withAnimation(.easeInOut(duration: 0.35)) {
          scrollToNowTick &+= 1
        }
      }
    }
  }

  func requestDailyGoalPromptIfNeeded() {
    guard DayGoalPreferences.showDailyGoalPopups else {
      pendingGoalPromptDay = nil
      return
    }

    let today = timelineDisplayDate(from: Date())
    let promptDay = cachedDayFormatter.string(from: today)

    guard UserDefaults.standard.string(forKey: dailyGoalPromptHandledDayKey) != promptDay
    else {
      return
    }
    guard pendingGoalPromptDay != promptDay else { return }
    guard goalFlowPresentation == nil else { return }

    // Three database reads; they run off the main thread because this is called from onAppear.
    let requiredActiveDays = FeatureAccessRequirements.dayGoalRequiredActiveDays
    let maxSkips = FeatureAccessRequirements.dayGoalMaxConsecutiveSkips
    Task {
      let decision = await Task.detached(priority: .userInitiated) {
        let store = StorageManager.shared
        return DailyGoalPromptDecision.evaluate(
          hasPlan: store.fetchDayGoalPlan(forDay: promptDay) != nil,
          activeDays: store.countDistinctTimelineDays(excludingDay: promptDay),
          skipStreak: store.consecutiveSkippedDayGoalCount(before: promptDay, limit: maxSkips),
          requiredActiveDays: requiredActiveDays,
          maxSkips: maxSkips
        )
      }.value
      // State may have moved on while the reads ran.
      guard pendingGoalPromptDay != promptDay, goalFlowPresentation == nil else { return }
      switch decision {
      case .alreadyPlanned:
        markDailyGoalPromptHandled(day: promptDay)
      case .notYet:
        return
      case .prompt:
        presentDailyGoalPrompt(promptDay: promptDay, today: today)
      }
    }
  }

  private func presentDailyGoalPrompt(promptDay: String, today: Date) {
    selectedActivity = nil
    setSelectedDate(today)
    setTimelineMode(.day)

    if selectedIcon != .timeline {
      withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
        selectedIcon = .timeline
      }
    }

    pendingGoalPromptDay = promptDay
  }

  func markDailyGoalPromptHandled(day: String) {
    UserDefaults.standard.set(day, forKey: dailyGoalPromptHandledDayKey)
    if pendingGoalPromptDay == day {
      pendingGoalPromptDay = nil
    }
  }

  func performIdleResetAndScroll() {
    // Switch to today
    setSelectedDate(timelineDisplayDate(from: Date()))
    // Clear selection
    selectedActivity = nil
    // Nudge timeline to scroll to now after it reloads
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      #if DEBUG
        print("[MainView] performIdleResetAndScroll -> nudging scrollToNowTick")
      #endif
      withAnimation(.easeInOut(duration: 0.35)) {
        scrollToNowTick &+= 1
      }
    }
  }

  func performInitialScrollIfNeeded() {
    // Check all conditions for initial scroll:
    // 1. Timeline is visible (not in settings)
    // 2. No modal is open
    // 3. Selected date is today
    guard selectedIcon != .settings,
      !showDatePicker,
      timelineIsToday(selectedDate)
    else {
      return
    }

    // Mark that we've attempted initial scroll
    didInitialScroll = true

    // Wait for layout to settle after animations complete
    // Increased delay to ensure ScrollView is fully ready on cold start
    #if DEBUG
      print("[MainView] performInitialScrollIfNeeded scheduled with 1.5s delay")
    #endif
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      #if DEBUG
        print("[MainView] performInitialScrollIfNeeded firing -> nudging scrollToNowTick")
      #endif
      withAnimation(.easeInOut(duration: 0.35)) {
        scrollToNowTick &+= 1
      }
    }
  }
}

enum DailyGoalPromptDecision: Equatable {
  case alreadyPlanned
  case notYet
  case prompt

  /// New users wait until Dayflow has real data (a few prior days of activity), and five skips in
  /// a row stop auto-prompting. Neither marks the day handled, so prompting resumes later.
  static func evaluate(
    hasPlan: Bool, activeDays: Int, skipStreak: Int, requiredActiveDays: Int, maxSkips: Int
  ) -> DailyGoalPromptDecision {
    if hasPlan { return .alreadyPlanned }
    guard activeDays >= requiredActiveDays else { return .notYet }
    guard skipStreak < maxSkips else { return .notYet }
    return .prompt
  }
}
