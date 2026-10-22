import AppKit
import Sentry
import SwiftUI

extension MainView {
  // `mainLayout` is split into two chained computed properties because the
  // full modifier stack (20+ modifiers, several large inline closures) was
  // exceeding Swift's per-expression type-check budget. Each `some View`
  // boundary gives the solver a fresh, opaque anchor so the inner chain is
  // type-checked in isolation. Closure bodies that ran long (onAppear, the
  // tab-selection onChange, selectedDate onChange, toast overlay) are also
  // extracted to named methods / computed properties below for the same
  // reason.
  var mainLayout: some View {
    mainLayoutCore
      .environmentObject(retryCoordinator)
  }

  // Layer 1: layout + visual overlays.
  private var mainLayoutWithOverlays: some View {
    contentStack
      .padding([.top, .trailing, .bottom], 15)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.clear)
      .ignoresSafeArea()
      .blur(radius: goalFlowPresentation == nil ? 0 : 10)
      .allowsHitTesting(goalFlowPresentation == nil)
      // Hero animation overlay for video expansion (Emil Kowalski: shared element transitions)
      .overlay { overlayContent }
      .overlay(alignment: .bottomTrailing) { timelineFailureToastOverlayContent }
      .overlay(alignment: .bottomTrailing) { screenRecordingPermissionNoticeOverlayContent }
      .overlay(alignment: .topTrailing) { weekTimelineFontSizeOverlay }
      .overlay { categoryEditorOverlay }
      .overlay { dailyBriefOverlayContent }
      .animation(.easeOut(duration: 0.22), value: dailyBrief.isPresented)
  }

  // Layer 2: sheet + lifecycle + notifications + state-change reactions.
  private var mainLayoutLifecycle: some View {
    mainLayoutWithOverlays
      .sheet(isPresented: $showDatePicker) {
        DatePickerSheet(
          selectedDate: Binding(
            get: { selectedDate },
            set: {
              lastDateNavMethod = "picker"
              setSelectedDate($0)
            }
          ),
          isPresented: $showDatePicker
        )
      }
      .onAppear(perform: performMainLayoutOnAppear)
      .onDisappear(perform: performMainLayoutOnDisappear)
      .onChange(of: inactivity.pendingReset) { _, fired in
        if fired, selectedIcon != .settings {
          performIdleResetAndScroll()
          InactivityMonitor.shared.markHandledIfPending()
        }
      }
      .onChange(of: selectedIcon) { oldIcon, newIcon in
        handleTabSelectionChange(newIcon)
        keepFlowAlive(leaving: oldIcon, entering: newIcon)
      }
      .onChange(of: selectedDate) { _, newDate in
        handleSelectedDateChange(newDate)
      }
      .onChange(of: refreshActivitiesTrigger) {
        updateCardsToReviewCount()
        loadWeeklyTrackedMinutes()
      }
      .onChange(of: selectedActivity?.id) {
        handleSelectedActivityIdChange()
      }
      // Second observer on selectedIcon: if user returns from Settings and a
      // reset was pending, perform it once. SwiftUI allows multiple onChange
      // handlers for the same value — they fire in declaration order.
      .onChange(of: selectedIcon) { _, newIcon in
        if newIcon != .settings, inactivity.pendingReset {
          performIdleResetAndScroll()
          InactivityMonitor.shared.markHandledIfPending()
        }
      }
  }

  // Split from the lifecycle chain so the type checker can handle each part.
  private var mainLayoutCore: some View {
    mainLayoutLifecycle
      .onReceive(NotificationCenter.default.publisher(for: .navigateToWeekly)) { _ in
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
          selectedIcon = .weekly
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { _ in
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
          selectedIcon = .settings
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .timelineZoomStep)) { notification in
        guard selectedIcon == .timeline else { return }
        let delta = notification.userInfo?["delta"] as? Int ?? 0
        setTimelineMode(timelineMode.zoomed(by: delta))
      }
      .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
        guard let number = notification.userInfo?["number"] as? Int,
          let icon = SidebarIcon.forCommandNumber(number),
          SidebarIcon.visibleIcons(hideFlow: SidebarIcon.hidesFlowByDefault).contains(icon)
        else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
          selectedIcon = icon
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .showTimelineFailureToast)) {
        handleShowTimelineFailureToastNotification($0)
      }
      .onReceive(NotificationCenter.default.publisher(for: .hideTimelineFailureToast)) { _ in
        handleHideTimelineFailureToastNotification()
      }
      .onReceive(NotificationCenter.default.publisher(for: .showScreenRecordingPermissionNotice)) {
        handleShowScreenRecordingPermissionNoticeNotification($0)
      }
      .onReceive(NotificationCenter.default.publisher(for: .timelineDataUpdated)) {
        handleTimelineDataUpdatedNotification($0)
      }
      .onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in
        handleAppDidBecomeActive()
      }
  }

  // MARK: - Extracted overlays and event handlers
  //
  // Each of these corresponds to a closure or inline view that used to live
  // inline in the `mainLayout` modifier chain. Extraction is load-bearing:
  // without it, the combined type-check of `mainLayout`'s modifier chain +
  // each closure's body exceeded Swift's per-expression solver budget.

  @ViewBuilder
  private var timelineFailureToastOverlayContent: some View {
    if let payload = timelineFailureToastPayload {
      TimelineFailureToastView(
        payload: payload,
        onOpenSettings: { handleTimelineFailureToastOpenSettings(payload) },
        onCopyCommand: {
          AnalyticsService.shared.capture(
            "llm_timeline_failure_toast_copied_command", payload.analyticsProps)
        },
        onDismiss: { handleTimelineFailureToastDismiss(payload) }
      )
      .padding(.trailing, 24)
      .padding(.bottom, 24)
      .transition(.move(edge: .trailing).combined(with: .opacity))
    }
  }

  @ViewBuilder
  private var screenRecordingPermissionNoticeOverlayContent: some View {
    if showScreenRecordingPermissionNotice {
      ScreenRecordingPermissionNoticeView(
        onOpenSettings: handleScreenRecordingPermissionNoticeOpenSettings,
        onDismiss: handleScreenRecordingPermissionNoticeDismiss
      )
      .padding(.trailing, 24)
      .padding(.bottom, 24)
      .transition(.move(edge: .trailing).combined(with: .opacity))
    }
  }

  private func performMainLayoutOnAppear() {
    syncCurrentUIContext()

    // screen viewed and initial timeline view
    AnalyticsService.shared.screen("timeline")
    AnalyticsService.shared.withSampling(probability: 0.01) {
      AnalyticsService.shared.capture(
        "timeline_viewed", ["date_bucket": dayString(selectedDate)])
    }
    // Orchestrated entrance animations following Emil Kowalski principles —
    // fast, under 300ms, natural spring motion, staggered by 50ms.
    withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0)) {
      logoScale = 1.0
      logoOpacity = 1
    }
    withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0).delay(0.1)) {
      timelineOffset = 0
      timelineOpacity = 1
    }
    withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0).delay(0.15)) {
      sidebarOffset = 0
      sidebarOpacity = 1
    }
    withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0).delay(0.2)) {
      contentOpacity = 1
    }

    if !didInitialScroll {
      performInitialScrollIfNeeded()
    }
    showScreenRecordingNoticeIfNeeded()
    startDayChangeTimer()
    loadWeeklyTrackedMinutes()
    updateCardsToReviewCount()
    requestDailyGoalPromptIfNeeded()
    dailyBrief.runIfNeeded(trigger: "launch")
    presentDailyBriefIfNeeded(source: "timeline_open")
  }

  private func performMainLayoutOnDisappear() {
    // Safety: stop timer if view disappears
    stopDayChangeTimer()
    reviewCountTask?.cancel()
    reviewCountTask = nil
    copyTimelineTask?.cancel()
    deleteTimelineTask?.cancel()
  }

  private func handleTabSelectionChange(_ newIcon: SidebarIcon) {
    // Clear tab-specific notification badges once the user visits the destination.
    if newIcon == .daily {
      if !consumePendingDailyRecapOpenIfNeeded(source: "daily_tab_selected") {
        NotificationBadgeManager.shared.clearDailyBadge()
      }
    }

    let tabName = newIcon.analyticsTabName
    syncCurrentUIContext(selectedTab: newIcon)

    SentryHelper.configureScope { scope in
      scope.setContext(
        value: [
          "active_view": tabName,
          "selected_date": dayString(selectedDate),
          "is_recording": appState.isRecording,
        ], key: "app_state")
    }

    let navBreadcrumb = Breadcrumb(level: .info, category: "navigation")
    navBreadcrumb.message = "Navigated to \(tabName)"
    navBreadcrumb.data = ["view": tabName]
    SentryHelper.addBreadcrumb(navBreadcrumb)

    AnalyticsService.shared.capture("tab_selected", ["tab": tabName])
    AnalyticsService.shared.screen(tabName)
    if newIcon == .timeline {
      AnalyticsService.shared.withSampling(probability: 0.01) {
        AnalyticsService.shared.capture(
          "timeline_viewed", ["date_bucket": dayString(selectedDate)])
      }
      updateCardsToReviewCount()
      loadWeeklyTrackedMinutes()
      presentDailyBriefIfNeeded(source: "timeline_open")
    } else {
      showTimelineReview = false
      // The brief lives over the Timeline panel, so leaving the tab closes it.
      if dailyBrief.isPresented {
        dailyBrief.dismiss()
      }
    }
  }

  private func handleSelectedDateChange(_ newDate: Date) {
    let changeStart = CFAbsoluteTimeGetCurrent()
    let oldDate = previousDate
    let oldDay = dayString(oldDate)
    let newDay = dayString(newDate)
    let oldWeekRange = cachedTimelineWeekRange

    if let method = lastDateNavMethod, method == "picker" {
      AnalyticsService.shared.capture(
        "date_navigation",
        [
          "method": method,
          "timeline_mode": timelineMode.rawValue,
          "from_day": oldDay,
          "to_day": newDay,
        ])
    }

    previousDate = newDate
    AnalyticsService.shared.withSampling(probability: 0.01) {
      AnalyticsService.shared.capture("timeline_viewed", ["date_bucket": newDay])
    }

    let newWeekRange = TimelineWeekRange.containing(newDate)
    let weekRangeChanged = newWeekRange != oldWeekRange

    timelinePerfLog(
      "selectedDateChange.begin mode=\(timelineMode.rawValue) old=\(oldDay) new=\(newDay) weekChanged=\(weekRangeChanged) navMethod=\(lastDateNavMethod ?? "nil")"
    )

    cachedTimelineWeekRange = newWeekRange
    updateCardsToReviewCount(trigger: "selectedDateChange")
    if weekRangeChanged {
      loadWeeklyTrackedMinutes(trigger: "selectedDateChange")
    }

    let durationMs = Int((CFAbsoluteTimeGetCurrent() - changeStart) * 1000)
    timelinePerfLog(
      "selectedDateChange.end mode=\(timelineMode.rawValue) old=\(oldDay) new=\(newDay) weekChanged=\(weekRangeChanged) duration_ms=\(durationMs)"
    )
  }

  private func handleSelectedActivityIdChange() {
    dismissFeedbackModal(animated: false)
    guard let a = selectedActivity else { return }
    GettingStarted.markCardOpened()
    let dur = a.endTime.timeIntervalSince(a.startTime)
    AnalyticsService.shared.capture(
      "activity_card_opened",
      [
        "activity_type": a.category,
        "duration_bucket": AnalyticsService.shared.secondsBucket(dur),
        "has_video": a.videoSummaryURL != nil,
      ])
  }

  private func handleTimelineDataUpdatedNotification(_ notification: Notification) {
    guard selectedIcon == .timeline else { return }
    if let refreshedDay = notification.userInfo?["dayString"] as? String {
      let selectedTimelineDay = DateFormatter.yyyyMMdd.string(
        from: timelineDisplayDate(from: selectedDate, now: Date())
      )
      guard refreshedDay == selectedTimelineDay else { return }
    }
    updateCardsToReviewCount()
    loadWeeklyTrackedMinutes()
  }

  private func handleShowTimelineFailureToastNotification(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
      let payload = TimelineFailureToastPayload(userInfo: userInfo)
    else {
      return
    }
    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
      timelineFailureToastPayload = payload
    }
  }

  private func handleHideTimelineFailureToastNotification() {
    guard timelineFailureToastPayload != nil else { return }
    withAnimation(.spring(response: 0.25, dampingFraction: 0.92)) {
      timelineFailureToastPayload = nil
    }
  }

  private func handleShowScreenRecordingPermissionNoticeNotification(_ notification: Notification) {
    let reason = notification.userInfo?["reason"] as? String
    if reason == ScreenRecordingPermissionNotice.captureFailingReason {
      screenCaptureIsFailing = true
    }
    showScreenRecordingNoticeIfNeeded()
  }

  private func showScreenRecordingNoticeIfNeeded() {
    guard !didDismissScreenRecordingPermissionNoticeThisSession else { return }
    guard !ScreenRecordingPermissionNotice.isGranted || screenCaptureIsFailing else {
      showScreenRecordingPermissionNotice = false
      return
    }
    guard AppState.shared.getSavedPreference() == true || appState.isRecording else { return }

    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
      showScreenRecordingPermissionNotice = true
    }
  }

  private func handleAppDidBecomeActive() {
    if ScreenRecordingPermissionNotice.isGranted && !screenCaptureIsFailing {
      showScreenRecordingPermissionNotice = false
      didDismissScreenRecordingPermissionNoticeThisSession = false
    }

    // Check if day changed while app was backgrounded
    handleMinuteTickForDayChange()
    requestDailyGoalPromptIfNeeded()
    // Ensure timer is running
    if dayChangeTimer == nil {
      startDayChangeTimer()
    }
    // Refresh weekly hours in case activities were added
    loadWeeklyTrackedMinutes()
    // A new day may have started while the app was in the background.
    dailyBrief.loadToday()
    dailyBrief.runIfNeeded(trigger: "app_active")
  }

  // MARK: - Daily brief

  /// Pops the brief up when the Timeline is shown and today's brief hasn't
  /// been seen yet. A brief that finishes while the user is already on the
  /// Timeline doesn't pop up; the ready notice announces it instead.
  func presentDailyBriefIfNeeded(source: String) {
    guard selectedIcon == .timeline,
      dailyBrief.shouldAutoPresent,
      !dailyBrief.isPresented,
      goalFlowPresentation == nil
    else {
      return
    }
    showTimelineReview = false
    dailyBrief.present(source: source)
  }

  /// The brief covers the main panel only: the 80pt sidebar column and the
  /// 15pt window padding stay visible, matching the "In-tab overlay" design.
  @ViewBuilder
  private var dailyBriefOverlayContent: some View {
    if dailyBrief.isPresented, goalFlowPresentation == nil {
      DailyBriefOverlay()
        .padding(.leading, 80)
        .padding([.top, .trailing, .bottom], 15)
        // Match the main panel, which also ignores the title bar inset.
        .ignoresSafeArea()
        .transition(.opacity)
        .zIndex(20)
    }
  }

  private func handleTimelineFailureToastOpenSettings(_ payload: TimelineFailureToastPayload) {
    AnalyticsService.shared.capture(
      "llm_timeline_failure_toast_clicked_settings", payload.analyticsProps)
    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
      selectedIcon = .settings
      timelineFailureToastPayload = nil
    }
    let settingsTab: Notification.Name =
      payload.destination == .account ? .openAccountSettings : .openProvidersSettings
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      NotificationCenter.default.post(name: settingsTab, object: nil)
    }
  }

  private func handleTimelineFailureToastDismiss(_ payload: TimelineFailureToastPayload) {
    AnalyticsService.shared.capture("llm_timeline_failure_toast_dismissed", payload.analyticsProps)
    withAnimation(.spring(response: 0.25, dampingFraction: 0.92)) {
      timelineFailureToastPayload = nil
    }
  }

  private func handleScreenRecordingPermissionNoticeOpenSettings() {
    AnalyticsService.shared.capture("screen_permission_notice_clicked_settings")
    didDismissScreenRecordingPermissionNoticeThisSession = true
    screenCaptureIsFailing = false
    withAnimation(.spring(response: 0.25, dampingFraction: 0.92)) {
      showScreenRecordingPermissionNotice = false
    }
    ScreenRecordingPermissionNotice.openSystemSettings()
  }

  private func handleScreenRecordingPermissionNoticeDismiss() {
    AnalyticsService.shared.capture("screen_permission_notice_dismissed")
    didDismissScreenRecordingPermissionNoticeThisSession = true
    screenCaptureIsFailing = false
    withAnimation(.spring(response: 0.25, dampingFraction: 0.92)) {
      showScreenRecordingPermissionNotice = false
    }
  }

  @ViewBuilder
  private var weekTimelineFontSizeOverlay: some View {
    if selectedIcon == .timeline, timelineMode == .week {
      VStack(alignment: .trailing, spacing: 6) {
        weekTimelineFontSizeSlider
        weekTimelineFontWeightSlider
      }
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.white.opacity(0.78))
          .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
      )
      .padding(.top, 58)
      .padding(.trailing, 24)
      .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
      .zIndex(20)
    }
  }

  private var weekTimelineFontSizeSlider: some View {
    HStack(spacing: 8) {
      weekTimelineFontOverlayIcon("textformat.size")

      Slider(
        value: Binding(
          get: {
            WeekTimelineFontSizePreference.clamped(weekTimelineFontSizeValue)
          },
          set: {
            weekTimelineFontSizeValue = WeekTimelineFontSizePreference.clamped($0)
          }
        ),
        in: WeekTimelineFontSizePreference.minimum...WeekTimelineFontSizePreference.maximum,
        step: 1
      )
      .frame(width: 148)

      Text("\(Int(WeekTimelineFontSizePreference.clamped(weekTimelineFontSizeValue)))px")
        .font(.custom("Nunito", size: 11).weight(.medium))
        .foregroundColor(Color(hex: "796E64"))
        .frame(width: 32, alignment: .trailing)
    }
  }

  private var weekTimelineFontWeightSlider: some View {
    HStack(spacing: 8) {
      weekTimelineFontOverlayIcon("bold")

      Slider(
        value: Binding(
          get: {
            Double(WeekTimelineFontWeightOption.option(for: weekTimelineFontWeightIndex).rawValue)
          },
          set: {
            weekTimelineFontWeightIndex =
              Double(WeekTimelineFontWeightOption.option(for: $0).rawValue)
          }
        ),
        in: WeekTimelineFontWeightOption.sliderRange,
        step: 1
      )
      .frame(width: 148)

      Text(WeekTimelineFontWeightOption.option(for: weekTimelineFontWeightIndex).title)
        .font(.custom("Nunito", size: 11).weight(.medium))
        .foregroundColor(Color(hex: "796E64"))
        .frame(width: 52, alignment: .trailing)
    }
  }

  private func weekTimelineFontOverlayIcon(_ systemName: String) -> some View {
    Image(systemName: systemName)
      .font(.system(size: 12, weight: .semibold))
      .foregroundColor(Color(hex: "796E64"))
      .frame(width: 16, height: 26)
  }

  private var timelineHeaderTrailingReservation: CGFloat {
    let measuredWidth = max(timelineHeaderTrailingWidth, 120)
    return measuredWidth + 18
  }

  private var timelineNavigationButtons: some View {
    HStack(spacing: 2) {
      // Back — plain chevron matching the Figma, with a 28×28 hit box around
      // the 14×14 glyph. `.contentShape(Rectangle())` makes the entire outer
      // frame tappable (including transparent space around the glyph).
      Button(action: {
        navigateTimeline(to: previousTimelineDate(), method: "prev")
      }) {
        Image("LeftArrow")
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
          .contentShape(Rectangle())
      }
      .buttonStyle(DayflowPressScaleButtonStyle())
      .hoverScaleEffect(scale: 1.02)
      .pointingHandCursorOnHover(reassertOnPressEnd: true)

      // Forward — same pattern; stays disabled when we're already on today.
      Button(action: {
        guard canNavigateTimelineForward else { return }
        navigateTimeline(to: nextTimelineDate(), method: "next")
      }) {
        Image("RightArrow")
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)
          .contentShape(Rectangle())
          .opacity(canNavigateTimelineForward ? 1 : 0.35)
      }
      .buttonStyle(DayflowPressScaleButtonStyle())
      .disabled(!canNavigateTimelineForward)
      .hoverScaleEffect(
        enabled: canNavigateTimelineForward,
        scale: 1.02
      )
      .pointingHandCursorOnHover(
        enabled: canNavigateTimelineForward,
        reassertOnPressEnd: true
      )
    }
  }

  // Calendar pill — Figma 1:1 visuals (fill #FFA777, icon 16×16, h=30, border
  // #F2D2BD). The arrowless card itself is rendered at the panel level so it
  // can own outside-click dismissal without taps leaking through to the
  // timeline below.
  private var timelineCalendarButton: some View {
    Button(action: {
      if showTimelineCalendarPopover {
        closeTimelineCalendarPopover()
      } else {
        openTimelineCalendarPopover()
      }
    }) {
      ZStack {
        Capsule(style: .continuous)
          .fill(timelineCalendarButtonFillColor)
          .overlay(
            Capsule(style: .continuous)
              .stroke(timelineCalendarButtonBorderColor, lineWidth: 1)
          )
          .shadow(
            color: timelineCalendarButtonShadowColor,
            radius: showTimelineCalendarPopover ? 8 : 0,
            x: 0,
            y: showTimelineCalendarPopover ? 2 : 0
          )

        Image("CalendarIcon")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
      }
      .frame(width: 36, height: 30)
      .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(
      DayflowPressScaleButtonStyle(
        pressedScale: 0.985,
        animation: .spring(response: 0.18, dampingFraction: 0.88)
      )
    )
    .pointingHandCursorOnHover(reassertOnPressEnd: true)
    .animation(timelineCalendarButtonStateAnimation, value: showTimelineCalendarPopover)
    .trackTimelineCalendarButtonFrame()
  }

  private var timelineCalendarButtonFillColor: Color {
    showTimelineCalendarPopover ? Color(hex: "FFB38E") : Color(hex: "FFA777")
  }

  private var timelineCalendarButtonBorderColor: Color {
    showTimelineCalendarPopover ? Color(hex: "E8BDA1") : Color(hex: "F2D2BD")
  }

  private var timelineCalendarButtonShadowColor: Color {
    showTimelineCalendarPopover ? .black.opacity(0.10) : .clear
  }

  private var timelineCalendarButtonStateAnimation: Animation {
    reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.14)
  }

  private var timelineCalendarPopoverOpenAnimation: Animation {
    reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.18)
  }

  private var timelineCalendarPopoverCloseAnimation: Animation {
    reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.12)
  }

  private var timelineCalendarPopoverTransition: AnyTransition {
    guard !reduceMotion else { return .opacity }

    return .asymmetric(
      insertion: .opacity
        .combined(with: .offset(y: -6))
        .animation(timelineCalendarPopoverOpenAnimation),
      removal: .opacity
        .combined(with: .offset(y: -4))
        .animation(timelineCalendarPopoverCloseAnimation)
    )
  }

  private func openTimelineCalendarPopover() {
    withAnimation(timelineCalendarPopoverOpenAnimation) {
      showTimelineCalendarPopover = true
    }
  }

  private func closeTimelineCalendarPopover() {
    withAnimation(timelineCalendarPopoverCloseAnimation) {
      showTimelineCalendarPopover = false
    }
  }

  private func timelineCalendarPopoverOverlay(panelWidth: CGFloat) -> some View {
    let cardWidth = TimelineCalendarPopover.preferredWidth
    let horizontalPadding: CGFloat = 12
    let maxX = max(
      horizontalPadding,
      panelWidth - cardWidth - horizontalPadding
    )
    let cardX = min(
      max(horizontalPadding, timelineCalendarButtonFrame.midX - (cardWidth / 2)),
      maxX
    )

    return ZStack(alignment: .topLeading) {
      if showTimelineCalendarPopover {
        Rectangle()
          .fill(Color.black.opacity(0.001))
          .contentShape(Rectangle())
          .onTapGesture {
            closeTimelineCalendarPopover()
          }

        TimelineCalendarPopover(
          isPresented: $showTimelineCalendarPopover,
          selectedDate: selectedDate,
          canSelectFutureDates: false,
          highlightsSelectedWeek: timelineMode == .week,
          onSelect: { date in
            let tappedDay = dayString(date)
            let currentDay = dayString(selectedDate)
            let tappedWeek = TimelineWeekRange.containing(date)
            let currentWeek = timelineWeekRange
            let weekChanged = tappedWeek != currentWeek

            timelinePerfLog(
              "calendarPopover.select tapped=\(tappedDay) current=\(currentDay) mode=\(timelineMode.rawValue) weekChanged=\(weekChanged)"
            )

            timelinePerfLog(
              "calendarPopover.navigateDispatch tapped=\(tappedDay) mode=\(timelineMode.rawValue) weekChanged=\(weekChanged)"
            )
            navigateTimeline(to: date, method: "picker")
            DispatchQueue.main.async {
              closeTimelineCalendarPopover()
            }
          }
        )
        .offset(x: cardX, y: timelineCalendarButtonFrame.maxY + 55)
        .transition(timelineCalendarPopoverTransition)
        .zIndex(1)
      }
    }
    .allowsHitTesting(showTimelineCalendarPopover)
  }

  private var timelineModeSwitch: some View {
    HStack(spacing: 0) {
      ForEach(TimelineMode.allCases) { mode in
        let isSelected = timelineMode == mode

        Button(action: {
          setTimelineMode(mode)
        }) {
          ZStack {
            if isSelected {
              Capsule(style: .continuous)
                .fill(
                  LinearGradient(
                    colors: [
                      Color(hex: "FFB18D").opacity(0.6),
                      Color(hex: "FFA46F"),
                      Color(hex: "FFB18D"),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                  )
                )
                .shadow(color: Color(hex: "E89A6C").opacity(0.18), radius: 4, x: 0, y: 1)
                .matchedGeometryEffect(
                  id: "timeline_mode_highlight",
                  in: timelineModeSwitchNamespace
                )
            }

            Text(mode.title)
              .font(.custom("Nunito", size: 12).weight(.medium))
              .foregroundColor(isSelected ? .white : Color(hex: "796E64"))
              // Concrete width (52pt × 2 = 104pt container) instead of
              // `.frame(maxWidth: .infinity)`. The infinity was being fought
              // by the `.fixedSize(horizontal: true)` ancestor on
              // `timelineLeadingControls`, which resolved the toggle's
              // ideal width as ~0 and collapsed the cream background +
              // "Day" label. Three independent parallel investigations
              // converged on this exact change.
              .frame(width: 52, height: 30)
          }
          .contentShape(Capsule(style: .continuous))
        }
        // Reverted to PlainButtonStyle: DayflowPressScaleButtonStyle — even
        // with `enabled: false` — still wraps the label in `.animation(...)`,
        // which appears to conflict with the outer `.animation(...)` tied to
        // the matchedGeometryEffect gradient. The press-darkening flash is
        // the accepted tradeoff for a correctly-behaving matched slide.
        .buttonStyle(PlainButtonStyle())
        .hoverScaleEffect(scale: 1.01)
        .pointingHandCursorOnHover(reassertOnPressEnd: true)
      }
    }
    .frame(width: 104, height: 30)
    .background(Color(hex: "FFEFE4"))
    .clipShape(Capsule(style: .continuous))
    .overlay(
      Capsule(style: .continuous)
        .stroke(Color(hex: "F2D2BD"), lineWidth: 1)
    )
    .animation(timelineModeSwitchAnimation, value: timelineMode)
  }

  private var timelineTodayButton: some View {
    Button(action: {
      navigateTimeline(to: timelineDisplayDate(from: Date()), method: "today")
    }) {
      Text("Today")
        .font(.custom("Nunito", size: 12).weight(.medium))
        .foregroundColor(Color(hex: "796E64"))
        .padding(.horizontal, 10)
        // Explicit width pinned (natural ~52pt + 4pt safety margin). Same
        // rationale as the calendar pill: under the ancestor's `.fixedSize`
        // inside a `ViewThatFits`, implicit widths can resolve to unstable
        // values mid-transition, nudging the Day/Week toggle's position and
        // desyncing its `matchedGeometryEffect` anchors during a mode flip.
        .frame(width: 56, height: 30)
        .background(Color(hex: "FFEFE4"))
        .clipShape(Capsule(style: .continuous))
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color(hex: "F2D2BD"), lineWidth: 1)
        )
    }
    .buttonStyle(DayflowPressScaleButtonStyle(pressedScale: 0.97))
    .hoverScaleEffect(scale: 1.02)
    .pointingHandCursorOnHover(reassertOnPressEnd: true)
  }

  private var timelineHeaderDateLabel: some View {
    Text(timelineTitleText)
      .font(.custom("InstrumentSerif-Regular", size: 26))
      .foregroundColor(Color.black)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .onTapGesture {
        guard timelineMode == .day else { return }
        showDatePicker = true
        lastDateNavMethod = "picker"
      }
  }

  private var timelineContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      TabFilterBar(
        categories: categoryStore.editableCategories,
        idleCategory: categoryStore.idleCategory,
        onManageCategories: { showCategoryEditor = true }
      )
      .padding(.leading, 10)
      .opacity(contentOpacity)

      ZStack(alignment: .topLeading) {
        switch timelineMode {
        case .day:
          CanvasTimelineDataView(
            selectedDate: $selectedDate,
            selectedActivity: $selectedActivity,
            scrollToNowTick: $scrollToNowTick,
            hasAnyActivities: $hasAnyActivities,
            refreshTrigger: $refreshActivitiesTrigger,
            weeklyHoursFrame: weeklyHoursFrame,
            weeklyHoursIntersectsCard: $weeklyHoursIntersectsCard
          )
          // Day is the zoomed-IN view (1/7 of a week). Entering Day feels
          // like diving into a single column: grow from 0.95 → 1 + fade in.
          // Exiting Day (to Week) shrinks 1 → 0.95 + fade out, matching the
          // "pull back to see more" feel when Week slides in behind it.
          .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
          .zIndex(timelineMode == .day ? 1 : 0)

        case .week:
          WeekTimelineGridView(
            selectedDate: $selectedDate,
            selectedActivity: $selectedActivity,
            hasAnyActivities: $hasAnyActivities,
            refreshTrigger: $refreshActivitiesTrigger,
            weekRange: timelineWeekRange,
            onSelectActivity: selectTimelineActivity,
            onClearSelection: { clearTimelineSelection() },
            weeklyHoursFrame: weeklyHoursFrame,
            weeklyHoursIntersectsCard: $weeklyHoursIntersectsCard,
            hideCardsForModeSwitch: hideWeekCardsDuringModeSwitch
          )
          // Week is the zoomed-OUT view (7 days). Entering Week from Day
          // feels like pulling back: start at 1.05 (slightly too large) and
          // settle to 1 + fade in. Exiting Week grows to 1.05 + fade out,
          // matching the "dive in" feel when Day settles to 1 behind it.
          .transition(.opacity.combined(with: .scale(scale: 1.05, anchor: .center)))
          .zIndex(timelineMode == .week ? 1 : 0)
        }
      }
      .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .environmentObject(categoryStore)
      .opacity(contentOpacity)
      .animation(timelineModeContentAnimation, value: timelineMode)
    }
    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var timelineFooter: some View {
    let weeklyHoursOpacity =
      weeklyHoursFadeOpacity * (weeklyHoursIntersectsCard ? 0 : 1)

    return ZStack(alignment: .bottom) {
      HStack(alignment: .bottom) {
        weeklyHoursText
          .opacity(contentOpacity * weeklyHoursOpacity)

        Spacer()

        copyTimelineButton
          .opacity(contentOpacity)
      }
      .padding(.horizontal, 24)

      if timelineMode == .day, cardsToReviewCount > 0 {
        CardsToReviewButton(count: cardsToReviewCount) {
          withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showTimelineReview = true
          }
        }
        .opacity(contentOpacity)
      }
    }
    .padding(.bottom, 17)
    .allowsHitTesting(true)
  }

  private func timelineRightColumn(geo: GeometryProxy) -> some View {
    ZStack(alignment: .topLeading) {
      if timelineInspectorWidth > 0 {
        Color.white.opacity(0.7)
      }

      switch timelineMode {
      case .day:
        dayTimelineInspectorContent(geo: geo)
      case .week:
        weekTimelineInspectorContent(geo: geo)
      }
    }
    .frame(width: timelineInspectorWidth)
    .frame(maxHeight: .infinity)
    .opacity(contentOpacity)
    .clipped()
    .clipShape(
      UnevenRoundedRectangle(
        cornerRadii: .init(
          topLeading: 0,
          bottomLeading: 0, bottomTrailing: 8, topTrailing: 8
        )
      )
    )
    .contentShape(
      UnevenRoundedRectangle(
        cornerRadii: .init(
          topLeading: 0,
          bottomLeading: 0, bottomTrailing: 8, topTrailing: 8
        )
      )
    )
  }

  @ViewBuilder
  private func dayTimelineInspectorContent(geo: GeometryProxy) -> some View {
    if let activity = selectedActivity {
      timelineActivityInspector(activity: activity, geo: geo)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    } else {
      DaySummaryView(
        selectedDate: selectedDate,
        categories: categoryStore.categories,
        storageManager: StorageManager.shared,
        cardsToReviewCount: cardsToReviewCount,
        reviewRefreshToken: reviewSummaryRefreshToken,
        onReviewTap: {
          guard cardsToReviewCount > 0 else { return }
          withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showTimelineReview = true
          }
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
  }

  @ViewBuilder
  private func weekTimelineInspectorContent(geo: GeometryProxy) -> some View {
    if let activity = selectedActivity, isWeekTimelineInspectorVisible {
      timelineActivityInspector(activity: activity, geo: geo)
        .id(activity.id)
        .opacity(weekInspectorContentVisible ? 1 : 0)
        .offset(x: weekInspectorContentVisible ? 0 : 10)
        .animation(inspectorContentAnimation, value: weekInspectorContentVisible)
        .transition(.opacity.combined(with: .offset(x: 10)))
    }
  }

  private func timelineActivityInspector(activity: TimelineActivity, geo: GeometryProxy)
    -> some View
  {
    ZStack(alignment: .bottom) {
      ActivityCard(
        activity: activity,
        maxHeight: geo.size.height,
        scrollSummary: true,
        hasAnyActivities: hasAnyActivities,
        onCategoryChange: { category, activity in
          handleCategoryChange(to: category, for: activity)
        },
        onNavigateToCategoryEditor: {
          showCategoryEditor = true
        },
        onRetryBatchCompleted: { batchId in
          refreshActivitiesTrigger &+= 1
          if selectedActivity?.batchId == batchId {
            clearTimelineSelection()
          }
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .allowsHitTesting(!feedbackModalVisible)
      .padding(.bottom, rateSummaryFooterHeight)

      if !feedbackModalVisible {
        TimelineRateSummaryView(
          activityID: activity.id,
          onRate: handleTimelineRating,
          onDelete: handleTimelineDelete
        )
        .frame(maxWidth: .infinity)
        .allowsHitTesting(!feedbackModalVisible)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .bottomLeading) {
      if let direction = feedbackDirection, feedbackModalVisible {
        TimelineFeedbackModal(
          message: $feedbackMessage,
          shareLogs: $feedbackShareLogs,
          direction: direction,
          mode: feedbackMode,
          content: .timeline,
          onSubmit: handleFeedbackSubmit,
          onClose: { dismissFeedbackModal() }
        )
        .padding(.leading, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
  }

  private var overlayContent: some View {
    ZStack {
      VideoExpansionOverlay(
        expansionState: videoExpansionState,
        namespace: videoHeroNamespace
      )

      if selectedIcon == .timeline, showTimelineReview {
        TimelineReviewOverlay(
          isPresented: $showTimelineReview,
          selectedDate: selectedDate
        ) {
          updateCardsToReviewCount()
          reviewSummaryRefreshToken &+= 1
        }
        .environmentObject(categoryStore)
        .transition(.opacity)
        .zIndex(2)
      }

    }
  }

  @ViewBuilder
  private var categoryEditorOverlay: some View {
    if showCategoryEditor {
      ColorOrganizerRoot(
        presentationStyle: .sheet,
        onDismiss: { showCategoryEditor = false }, completionButtonTitle: String(localized: "Done"),
        showsTitles: true
      )
      .environmentObject(categoryStore)
      // Removed .contentShape(Rectangle()) and .onTapGesture to allow keyboard input
    }
  }
}

/// Bottom-right card for timeline failures the person has to fix themselves
/// (signed out, out of credits...). Shows numbered steps when there's a
/// concrete fix, otherwise a button into Settings.
private struct TimelineFailureToastView: View {
  @Environment(\.dayflowTheme) private var theme
  let payload: TimelineFailureToastPayload
  let onOpenSettings: () -> Void
  let onCopyCommand: () -> Void
  let onDismiss: () -> Void
  @State private var didCopy = false

  private var actionTitle: String {
    payload.destination == .account
      ? String(localized: "Open Account") : String(localized: "Open Provider Settings")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      Text(payload.message)
        .font(.custom("Figtree", size: 13))
        .foregroundStyle(theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      if payload.steps.isEmpty {
        buttons
      } else {
        steps
      }

      footer
    }
    .promptCardStyle(width: 360)
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      providerLogo
        .frame(width: 22, height: 22)

      Text(payload.title ?? String(localized: "Dayflow needs a hand"))
        .font(.custom("Figtree", size: 15).weight(.semibold))
        .foregroundStyle(theme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 8)

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(theme.textMuted)
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
    }
  }

  @ViewBuilder
  private var providerLogo: some View {
    let name = payload.providerName.lowercased()
    if name.contains("claude") {
      Image("ClaudeLogo").resizable().scaledToFit()
    } else if name.contains("chatgpt") || name.contains("codex") {
      Image("ChatGPTLogo").resizable().scaledToFit()
    } else if name.contains("gemini") || name.contains("gemma") {
      Image("GeminiLogo").resizable().scaledToFit()
    } else if name.contains("dayflow") {
      Image("DayflowLogo").resizable().scaledToFit()
    } else {
      Image(systemName: "cpu")
        .font(.system(size: 15))
        .foregroundStyle(theme.textSecondary)
    }
  }

  // MARK: Steps

  private var steps: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(payload.steps.enumerated()), id: \.offset) { index, step in
        HStack(alignment: .top, spacing: 10) {
          stepNumber(index + 1)

          VStack(alignment: .leading, spacing: 8) {
            Text(step)
              .font(.custom("Figtree", size: 13))
              .foregroundStyle(theme.textPrimary)
              .fixedSize(horizontal: false, vertical: true)

            if index == 0, let command = payload.command {
              commandBox(command)
            }
          }
        }
      }

      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 18))
          .foregroundStyle(theme.accent)
          .frame(width: 20, height: 20)

        Text("Dayflow catches up automatically")
          .font(.custom("Figtree", size: 13))
          .foregroundStyle(theme.textPrimary)
          .padding(.top, 1)
      }
    }
  }

  private func stepNumber(_ number: Int) -> some View {
    Text("\(number)")
      .font(.custom("Figtree", size: 11).weight(.semibold))
      .foregroundStyle(theme.accent)
      .frame(width: 20, height: 20)
      .background(Circle().fill(theme.accent.opacity(0.14)))
  }

  private func commandBox(_ command: String) -> some View {
    HStack(spacing: 8) {
      Text(command)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(theme.textPrimary)
        .textSelection(.enabled)
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer(minLength: 4)

      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        onCopyCommand()
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
          didCopy = false
        }
      } label: {
        HStack(spacing: 4) {
          if didCopy {
            Image(systemName: "checkmark")
              .font(.system(size: 10, weight: .semibold))
          } else {
            Image("Copy")
              .resizable()
              .scaledToFit()
              .frame(width: 11, height: 11)
          }
          Text(didCopy ? String(localized: "Copied") : String(localized: "Copy"))
            .font(.custom("Figtree", size: 11).weight(.medium))
        }
        .foregroundStyle(theme.secondaryButtonText)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(theme.secondaryButtonFill))
        .overlay(
          RoundedRectangle(cornerRadius: 5)
            .strokeBorder(theme.secondaryButtonBorder, lineWidth: 0.75)
        )
        .fixedSize()
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
    }
    .padding(.leading, 10)
    .padding(.trailing, 5)
    .frame(height: 32)
    .background(RoundedRectangle(cornerRadius: 6).fill(theme.controlFill))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(theme.controlBorder, lineWidth: 0.75)
    )
  }

  // MARK: Buttons (no steps)

  private var buttons: some View {
    HStack(spacing: 8) {
      Button(action: onDismiss) {
        Text("Not now")
          .font(.custom("Figtree", size: 13).weight(theme.isDark ? .medium : .regular))
          .foregroundStyle(theme.secondaryButtonText)
          .frame(maxWidth: .infinity)
          .frame(height: 34)
          .background(Capsule().fill(theme.secondaryButtonFill))
          .overlay(
            Capsule().strokeBorder(theme.secondaryButtonBorder, lineWidth: theme.isDark ? 1 : 0.75))
      }
      .buttonStyle(.plain)
      .pointingHandCursor()

      Button(action: onOpenSettings) {
        Text(actionTitle)
          .font(.custom("Figtree", size: 13).weight(.medium))
          .foregroundStyle(theme.primaryButtonText)
          .lineLimit(1)
          .frame(maxWidth: .infinity)
          .frame(height: 34)
          .background(Capsule().fill(theme.primaryButtonFill))
          .overlay(InnerGlow(shape: Capsule(), color: theme.primaryButtonInnerGlow, radius: 3))
          .overlay(
            Capsule().strokeBorder(theme.primaryButtonBorder, lineWidth: theme.isDark ? 0.5 : 0.75))
      }
      .buttonStyle(.plain)
      .pointingHandCursor()
    }
  }

  // MARK: Footer

  private var footer: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(theme.accent)
        .frame(width: 6, height: 6)

      if let waiting = waitingText {
        Text("\(waiting) waiting to process")
          .font(.custom("Figtree", size: 12))
          .foregroundStyle(theme.textSecondary)
        Spacer(minLength: 8)
        Text("Retries on its own")
          .font(.custom("Figtree", size: 12))
          .foregroundStyle(theme.textMuted)
      } else {
        Text("Dayflow catches up automatically")
          .font(.custom("Figtree", size: 12))
          .foregroundStyle(theme.textSecondary)
        Spacer(minLength: 0)
      }
    }
    .padding(.top, 10)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(theme.controlBorder)
        .frame(height: 0.5)
    }
  }

  /// "25 min", "3 hrs", "1 day". Nil when nothing is waiting.
  private var waitingText: String? {
    let minutes = payload.waitingSeconds / 60
    guard minutes > 0 else { return nil }
    if minutes < 60 {
      return String(localized: "\(minutes) min")
    }
    let hours = minutes / 60
    if hours < 24 {
      return hours == 1 ? String(localized: "1 hr") : String(localized: "\(hours) hrs")
    }
    return String(localized: "1 day")
  }
}

private struct ScreenRecordingPermissionNoticeView: View {
  @Environment(\.dayflowTheme) private var theme
  let onOpenSettings: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "record.circle.fill")
          .font(.system(size: 15))
          .foregroundColor(Color(hex: "C7352D"))
          .padding(.top, 2)

        VStack(alignment: .leading, spacing: 3) {
          Text("Screen recording access needed")
            .font(.custom("Figtree", size: 13))
            .fontWeight(.semibold)
            .foregroundColor(theme.textPrimary)

          Text("Dayflow cannot update your timeline until access is restored.")
            .font(.custom("Figtree", size: 12))
            .foregroundColor(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(theme.textMuted)
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .hoverScaleEffect(scale: 1.02)
        .pointingHandCursorOnHover(reassertOnPressEnd: true)
      }

      DayflowSurfaceButton(
        action: onOpenSettings,
        content: {
          HStack(spacing: 6) {
            Image(systemName: "gearshape")
              .font(.system(size: 12))
            Text("Open System Settings")
              .font(.custom("Figtree", size: 12))
              .fontWeight(.semibold)
          }
        },
        background: theme.primaryButtonFill,
        foreground: theme.primaryButtonText,
        borderColor: .clear,
        cornerRadius: 8,
        horizontalPadding: 14,
        verticalPadding: 8,
        showOverlayStroke: true
      )
    }
    .padding(14)
    .frame(width: 360, alignment: .leading)
    .background(theme.popoverFill)
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(theme.popoverBorder, lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
  }
}

extension MainView {
  /// Keeps Flow loaded for `flowKeepAlive` after the user leaves its tab, then lets it go.
  func keepFlowAlive(leaving oldIcon: SidebarIcon, entering newIcon: SidebarIcon) {
    if newIcon == .flow {
      flowTeardown?.cancel()
      flowTeardown = nil
      flowAlive = true
    } else if oldIcon == .flow {
      flowTeardown?.cancel()
      flowTeardown = Task { @MainActor in
        try? await Task.sleep(for: MainView.flowKeepAlive)
        guard !Task.isCancelled, selectedIcon != .flow else { return }
        flowAlive = false
      }
    }
  }
}
