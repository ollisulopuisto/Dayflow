"""Fork invariants that an upstream release merge must preserve."""
import pathlib
import plistlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class UpstreamMergeContractTests(unittest.TestCase):
    def test_release_metadata_and_update_feed(self):
        info = plistlib.loads((ROOT / 'Dayflow/Dayflow/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleShortVersionString'], '2.8.0')
        self.assertEqual(info['CFBundleVersion'], '172')
        self.assertNotIn('SUFeedURL', info)
        self.assertFalse(info['SUEnableAutomaticChecks'])
        self.assertFalse(info['SUAutomaticallyUpdate'])
        project = (ROOT / 'Dayflow/Dayflow.xcodeproj/project.pbxproj').read_text()
        self.assertEqual(project.count('CURRENT_PROJECT_VERSION = 172;'), 6)
        self.assertEqual(project.count('MARKETING_VERSION = 2.8.0;'), 6)
        self.assertIn('ONLY_ACTIVE_ARCH = NO;', project)

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

    def test_no_unresolved_conflicts(self):
        result = subprocess.run(['git', 'diff', '--check', 'HEAD'], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
