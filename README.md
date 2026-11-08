# Dayflow

Dayflow is a macOS work journal. It captures screen activity, uses a chosen AI
provider to turn it into a timeline, and lets you search, review and ask questions
about your day. You can pause recording; it is not a timer you start for each task.

This is Olli Sulopuisto's fork of [Jerry Liu's Dayflow](https://github.com/JerryZLiu/Dayflow).
It keeps the upstream app and adds timeline search, local CLI/MCP access, remote
Studio batch processing and fixes for this fork's capture and release workflows.
The upstream website, Homebrew cask and downloads are not this fork's builds.

## Install

The app target supports macOS 14 or later. This fork's release workflow builds
**Apple Silicon (arm64)** DMGs; it does not currently deliver Intel binaries.

1. Open this repository's [Releases](../../releases) and choose the build you need.
   Manual builds can be unpublished drafts, visible only to repository users with
   write access. A missing public download does not mean a draft build is public.
2. Download the DMG and its `.sha256` file. From their download folder, check it:
   ```sh
   shasum -a 256 -c Dayflow-<build-name>.dmg.sha256
   ```
   Replace the example filename with the actual checksum filename.
3. Open the DMG and drag Dayflow into Applications.
4. Follow onboarding to choose an AI provider and grant the permissions requested
   for your capture mode, including Screen Recording and Accessibility where used.

Release builds require Developer ID signing, Apple notarization and a stapled
DMG ticket. Use a build from this fork deliberately; do not assume the upstream
app's automatic update feed will keep it current. CI release delivery does not
publish a Sparkle appcast. See [release instructions](docs/RELEASE.md).

## What it does

- **Timeline:** activity cards with summaries, categories, search and a record of
  what happened when. Export timeline entries as Markdown.
- **Daily and weekly review:** standup notes, priorities, blockers, activity grids
  and weekly summaries drawn from the journal.
- **Chat:** ask questions about recorded work rather than manually finding each
  card. Availability and output depend on the selected provider.
- **Capture controls:** pause/resume recording and manage storage limits and old
  recordings. The app includes screenshot and Accessibility-based capture paths.
- **Provider choice:** Gemini, local Ollama/LM Studio-compatible endpoints,
  OpenAI-compatible endpoints such as SiliconFlow, and Codex or Claude CLI
  integrations. Install and authenticate external tools separately when needed.
- **CLI and MCP:** the bundled `dayflow` helper exposes journal access to tools.
  Configure access and editing in Settings under MCP / CLI; enabling editing is
  separate from simply connecting a client.
- **Studio processing:** optional batch transfer to a configured Studio queue for
  analysis elsewhere. This is a network feature, not an on-device privacy mode.
- **What's New:** release notes are bundled with the app and available from Help.

AI summaries can be wrong or incomplete. Check the underlying activity before
using the journal as evidence for a report, invoice or decision.

## Privacy and network access

Journal data and recordings are stored under:

```text
~/Library/Application Support/Dayflow/
```

Local storage does not mean every feature is offline:

- A cloud AI provider receives the screen content or text needed for its requests.
  Codex and Claude CLI tools run locally but can send requests to their cloud
  services. A local model endpoint is the option for on-device model processing.
- Studio sends queued activity to the configured server. Choose and protect that
  endpoint as carefully as the Mac holding the journal.
- The app contains PostHog analytics and Sentry crash reporting. The shared
  telemetry preference defaults to enabled; reporting also depends on the build's
  configured keys/DSN. Review the preference in Settings. Crash reporting can
  include Apple's crash report after a crash. Do not treat local AI as a promise
  of zero network traffic.
- CLI/MCP clients can receive private journal content. Review their access and the
  separate editing setting before connecting them.

Avoid recording material you should not retain or send to a provider. Pause
capture for sensitive work, review storage settings, and protect local backups.
Do not put API keys, screen recordings or private journal exports in bug reports.

## Build from source

Use macOS with Xcode and its command-line tools. Xcode resolves the Swift package
requirements in the project. From a checkout of this fork:

```sh
git clone https://github.com/ollisulopuisto/Dayflow.git
cd Dayflow
open Dayflow/Dayflow.xcodeproj
```

Select the **Dayflow** scheme and your development signing team. The local build
script also supports a stable team/bundle ID override:

```sh
./scripts/build_local.sh --team YOURTEAMID --bundle-id com.example.DayflowLocal --open
```

For a compile-only build without signing:

```sh
./scripts/build_local.sh --unsigned
```

Unsigned builds are not distributable releases and may not retain Screen
Recording permission across rebuilds. Keep a stable identity/bundle ID for a
local app you use daily. See [RELEASE.md](docs/RELEASE.md) for the build output,
required release secrets, notarization and draft delivery.

## Test and contribute

The test runner needs macOS/Xcode. For unit tests without UI tests:

```sh
xcodebuild -project Dayflow/Dayflow.xcodeproj -scheme Dayflow \
  -configuration Debug -destination 'platform=macOS' \
  -skip-testing:DayflowUITests CODE_SIGNING_ALLOWED=NO test
python3 -m unittest discover -s scripts/tests -v
python3 scripts/ci/test_upstream_merge_contract.py
```

[CI](.github/workflows/build-macos.yml) selects affected XCTest suites for routine
changes and runs the full suite on its scheduled job. Keep code changes in PRs
and describe how they were tested. Documentation-only PRs do not create releases.

- [Changelog](CHANGELOG.md)
- [Release and signing guide](docs/RELEASE.md)
- [Performance notes](docs/PERFORMANCE.md)

## License

[MIT](LICENSE), retaining the upstream copyright notice.
