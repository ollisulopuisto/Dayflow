"""Portable source guard; native XCTest is the behavioral acceptance."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class QuitShortcutContract(unittest.TestCase):
    def test_quit_reaches_normal_termination_not_soft_hide(self):
        source = (ROOT/'Dayflow/Dayflow/App/AppDelegate.swift').read_text()
        body = source.split('  func applicationShouldTerminate(')[1].split('// MARK:')[0]
        self.assertIn('return .terminateNow', body)
        self.assertIn('guard confirm() else { return .terminateCancel }', body)
        self.assertIn('Command-W or click the red close button', body)
        self.assertIn('return alert.runModal() == .alertFirstButtonReturn', body)
        self.assertNotIn('NSApp.hide', body)
        self.assertNotIn('didSoftQuit', source)
    def test_menu_uses_registry_without_special_quit(self):
        source = (ROOT/'Dayflow/Dayflow/App/DayflowApp.swift').read_text()
        self.assertIn('CommandGroup(replacing: .appTermination)', source)
        self.assertIn('AppShortcutRegistry.quit.key', source)
        self.assertIn('AppShortcutRegistry.hide.key', source)
        self.assertNotIn('Quit Dayflow Completely', source)
        registry = (ROOT/'Dayflow/Dayflow/App/AppShortcutRegistry.swift').read_text()
        self.assertIn('static let quit = Binding(key: "q", modifiers: .command)', registry)
        self.assertIn('static let hide = Binding(key: "h", modifiers: .command)', registry)
        hide = registry.split('@MainActor static func hideApplication')[1]
        self.assertNotIn('terminate', hide)
if __name__ == '__main__':
    unittest.main()
