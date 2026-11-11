"""Fork invariants that an upstream release merge must preserve."""
import pathlib
import re
import plistlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class UpstreamMergeContractTests(unittest.TestCase):
    def test_release_metadata_and_update_feed(self):
        info = plistlib.loads((ROOT / 'Dayflow/Dayflow/Info.plist').read_bytes())
        latest_version = re.search(r'^## \[([^\]]+)\]', (ROOT / 'CHANGELOG.md').read_text(), re.MULTILINE).group(1)
        self.assertEqual(info['CFBundleShortVersionString'], latest_version)
        self.assertTrue(info['CFBundleVersion'].isdigit())
        self.assertNotIn('SUFeedURL', info)
        self.assertFalse(info['SUEnableAutomaticChecks'])
        self.assertFalse(info['SUAutomaticallyUpdate'])
        project = (ROOT / 'Dayflow/Dayflow.xcodeproj/project.pbxproj').read_text()
        self.assertEqual(project.count(f"CURRENT_PROJECT_VERSION = {info['CFBundleVersion']};"), 6)
        self.assertEqual(project.count(f"MARKETING_VERSION = {info['CFBundleShortVersionString']};"), 6)
        self.assertIn('ONLY_ACTIVE_ARCH = NO;', project)

    def test_bundled_release_notes_match_repository(self):
        self.assertEqual((ROOT / 'Dayflow/Dayflow/CHANGELOG.md').read_bytes(),
                         (ROOT / 'CHANGELOG.md').read_bytes())

    def test_recording_keeps_both_cleanup_paths(self):
        source = (ROOT / 'Dayflow/Dayflow/Core/Recording/ScreenRecorder.swift').read_text()
        self.assertIn('FrameStore.shared.releaseReadResources()', source)
        self.assertIn('AccessibilityRecorder.shared.start()', source)
        self.assertIn('AccessibilityRecorder.shared.stop()', source)
        self.assertIn('AccessibilityLogStore.shared.close()', source)

    def test_fork_timeline_regressions_remain_in_place(self):
        paths = [
            'Dayflow/Dayflow/Views/UI/CanvasTimelineDataView.swift',
            'Dayflow/Dayflow/Views/UI/MainView/WeekTimelineGridView.swift',
        ]
        for path in paths:
            source = (ROOT / path).read_text()
            self.assertIn('TimelineCardWindow', source, path)
            self.assertIn('TimelineSearch', source, path)
        types = (ROOT / 'Dayflow/Dayflow/Views/UI/CanvasTimelineTypes.swift').read_text()
        self.assertIn('enum TimelineCardWindow', types)
        self.assertIn('enum TimelineTimeLabelGeometry', types)

    def test_reveal_mask_uses_fractional_gradient_stops(self):
        source = (ROOT / 'Dayflow/Dayflow/Views/UI/DailyBrief/Docket/DocketEffects.swift').read_text()
        for numerator in (26, 65, 104):
            self.assertIn(f'location: {numerator}.0 / 130.0', source)
            self.assertNotIn(f'location: {numerator} / 130', source)

    def test_sync_preserves_privacy_and_capture_guards(self):
        app = (ROOT / 'Dayflow/Dayflow/App/AppDelegate.swift').read_text()
        self.assertIn('PrivacyShield.shared.start()', app)
        self.assertNotIn('SupportChatSession.shared.start()', app)
        self.assertNotIn('startFlowWaitlistMonitoring()', app)
        recorder = (ROOT / 'Dayflow/Dayflow/Core/Recording/ScreenRecorder.swift').read_text()
        self.assertIn('BrowserPrivacy.redactionLabel()', recorder)
        self.assertIn('await blockedBrowserWindow()', recorder)
        self.assertIn('if let masker = PrivacyShieldMaskerBox.shared.current()', recorder)
        self.assertIn('VTCreateCGImageFromCVPixelBuffer', recorder)
        self.assertIn('try await maskSecrets(in: image, using: masker)', recorder)
        self.assertNotIn('return placeholder ?? image', recorder)
        self.assertEqual(recorder.count('guard _captureGeneration == generation'), 2)
        self.assertIn('placeholder, capturedAt: captureTime, idleSecondsAtCapture: idleSecondsAtCapture,\n          generation: generation)', recorder)

    def test_docket_consent_captures_selected_thread_before_handoff(self):
        source = (ROOT / 'Dayflow/Dayflow/Core/DailyBrief/DailyBriefStore.swift').read_text()
        handoff = source[source.index('  func handOffDocket('):source.index('  private func finishDocketRun(')]
        self.assertLess(handoff.index('let agent = thread?.1 ?? pickedApp ?? docketAgent'),
                        handoff.index('try await ProviderConsentGate.requireCLI(tool)'))
        self.assertLess(handoff.index('try await ProviderConsentGate.requireCLI(tool)'),
                        handoff.index('performHandOffDocket(item'))
        self.assertIn('threadID: thread?.0, briefPickedApp:', handoff)
        self.assertIn('thread == nil ? docketHandoffMethod : .paste', handoff)
        self.assertIn('agent.threadLink(thread: threadID, folder: folder)', handoff)

    def test_no_unresolved_conflicts(self):
        result = subprocess.run(['git', 'diff', '--check', 'HEAD'], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
