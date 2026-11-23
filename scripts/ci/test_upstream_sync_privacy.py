"""Regression contracts for the privacy-sensitive upstream sync integration."""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class UpstreamSyncPrivacyTests(unittest.TestCase):
    def source(self, path):
        return (ROOT / 'Dayflow/Dayflow' / path).read_text()

    def test_custom_transport_does_not_bypass_first_send_consent(self):
        source = self.source('Core/AI/OpenAICompatibleProvider.swift')
        self.assertIn('LLMURLSession.data(for: urlRequest)', source)
        self.assertNotIn('URLSession.shared.data(for: urlRequest)', source)
        self.assertIn('if error is ProviderConsentError { throw error }', source)

    def test_health_probe_retains_network_and_provider_gate(self):
        self.assertIn('LLMURLSession.data(for: request)',
                      self.source('Core/AI/ProviderAvailability.swift'))

    def test_declined_consent_cannot_send_to_backup(self):
        source = self.source('Core/AI/LLMService.swift')
        start = source.index('  private func executeWithProviderBackup')
        end = source.index('      onPrimaryFailure(error)', start)
        self.assertIn('if error is ProviderConsentError', source[start:end])

    def test_api_keys_stay_in_headers(self):
        for path in ['Utilities/GeminiAPIHelper.swift', 'Core/AI/GemmaBackupProvider+Networking.swift']:
            source = self.source(path)
            self.assertNotIn('?key=', source, path)
            self.assertNotIn('&key=', source, path)
            self.assertIn('forHTTPHeaderField: "x-goog-api-key"', source, path)

    def test_both_video_paths_remain_disk_backed(self):
        source = self.source('Core/AI/GeminiDirectProvider+Transcription.swift')
        start = source.index('  struct CompressedBatchVideo')
        self.assertNotIn('Data(contentsOf:', source[start:])
        self.assertIn('let fileURL: URL', source[start:])
        self.assertIn('removeItem(at: video.fileURL)', source[start:])
        timeline = self.source('Core/AI/GeminiDirectProvider+Timeline.swift')
        self.assertIn('uploadAndAwait(video.fileURL', timeline)
        self.assertNotIn('video.data', timeline)
        self.assertIn('removeItem(at: video.fileURL)', timeline)

    def test_removed_paid_and_remote_features_are_not_resurrected(self):
        for path in ['Core/Flow/FlowAgentSettings.swift', 'Core/Flow/FlowDistractionAgent.swift',
                     'Core/PrivacyShield/PrivacyShieldModelStore.swift',
                     'Views/UI/SupportChatWebView.swift', 'System/ClaudeInstaller.swift']:
            self.assertFalse((ROOT / 'Dayflow/Dayflow' / path).exists(), path)
        for path in ['System/StatusBarController.swift', 'Core/Notifications/NotificationService.swift']:
            self.assertNotIn('FlowSessionMirror', self.source(path), path)

    def test_sign_in_requires_cli_consent(self):
        source = self.source('System/ProviderSignIn.swift')
        self.assertLess(source.index('try await ProviderConsentGate.requireCLI'),
                        source.index('launch(command, provider: provider)'))


if __name__ == '__main__':
    unittest.main()
