# Release Process

Dayflow releases are produced automatically by GitHub Actions. Pushing a tag
matching `v*` (e.g. `v2.7.8`) to this repository triggers the
[release workflow](.github/workflows/release.yml), which:

1. Builds the app with Xcode (Release configuration)
2. Codesigns it with a Developer ID certificate (if configured)
3. Creates a signed DMG with `create-dmg`
4. Notarizes the DMG with Apple notarytool (if credentials are configured)
5. Creates a GitHub Release and uploads the DMG as an asset
6. Optionally uploads dSYMs to Sentry for crash symbolication

## Making a release

1. Bump the version in `Dayflow/Dayflow.xcodeproj/project.pbxproj`
   (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`) and in
   `Dayflow/Dayflow/Info.plist` (`CFBundleShortVersionString` and
   `CFBundleVersion`).
2. Add a CHANGELOG entry under a new `## Unreleased` → `## vX.Y.Z` section.
3. Commit the changes:
   ```
   git commit -m "release: bump to vX.Y.Z (build N)"
   ```
4. Tag and push:
   ```
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
5. GitHub Actions builds the DMG and publishes the release. Check the
   [Actions tab](https://github.com/ollisulopuisto/Dayflow/actions) for progress.

The release appears at:
`https://github.com/ollisulopuisto/Dayflow/releases/tag/vX.Y.Z`

## Building locally

Use `scripts/build_local.sh` to build the app with the Release configuration
and Xcode's automatic signing. With no ref, it builds the current working tree,
including uncommitted edits. Pass a tag or commit to build that exact revision
in a temporary detached worktree without switching the current checkout:

```sh
git fetch origin --tags
./scripts/build_local.sh --open v2.7.21
```

The script prints the resulting `Dayflow.app` path. It stores DerivedData under
`~/Library/Developer/Xcode/DerivedData/Dayflow-local-<commit>`. The script builds
the app bundle only; it does not create a DMG or publish a release. If Xcode
reports a signing error, add a development certificate for your team in Xcode
under **Settings → Accounts → Manage Certificates**. A free Personal Team is
enough for a local development build, but not for a Developer ID release.
Get its team ID from `security find-identity -v -p codesigning`. If you use a
different team than the project, choose a unique bundle ID and pass both:

```sh
./scripts/build_local.sh --team YOURTEAMID --bundle-id com.example.DayflowLocal --open v2.7.21
```

This local bundle ID has separate app data and privacy permissions from the
released app. Keep the same development identity and bundle ID across rebuilds
so macOS can retain Screen Recording permission. For a compile-only build that
does not need stable permissions, pass `--unsigned`.

## Required repository secrets

Configure these in the repository settings → Secrets and variables → Actions:

| Secret | Purpose | Required? |
|--------|---------|-----------|
| `SIGNING_CERTIFICATE_P12` | Base64-encoded Developer ID Application `.p12` certificate | No (builds unsigned without it) |
| `SIGNING_CERTIFICATE_PASSWORD` | Password for the `.p12` | No (needed with the above) |
| `NOTARY_APPLE_ID` | Apple ID for notarization | No |
| `NOTARY_APP_PASSWORD` | App-specific password for notarization | No |
| `NOTARY_TEAM_ID` | Apple Developer Team ID | No |
| `DAYFLOW_BACKEND_URL` | Backend URL injected into `Info.plist` | No (app won't connect without it) |
| `POSTHOG_API_KEY` | PostHog analytics key injected into `Info.plist` | No |
| `SENTRY_DSN` | Sentry crash-reporting DSN injected into `Info.plist` | No |
| `SENTRY_AUTH_TOKEN` | Sentry auth token for dSYM upload | No |
| `SENTRY_ORG` | Sentry organization slug | No |
| `SENTRY_PROJECT` | Sentry project slug | No |

### Setting up the signing certificate

Export your Developer ID Application certificate + private key as a `.p12`:

```
security find-identity -v -p codesigning  # find your cert name
security export -t identities -o cert.p12 -k /path/to/keychain "Developer ID Application: ..."
base64 -i cert.p12 | pbcopy  # then paste into the secret
```

Import it in the workflow (already handled automatically when
`SIGNING_CERTIFICATE_P12` is set).

### Setting up notarization

Create a notarytool keychain profile locally, or provide `NOTARY_APPLE_ID`,
`NOTARY_APP_PASSWORD` (app-specific password), and `NOTARY_TEAM_ID` as secrets.
Without notarization, the DMG will still be built and attached to the release,
but macOS Gatekeeper will block it on first launch for end users.

## Sparkle auto-updates

Sparkle update signatures (`sign_update` + EdDSA private key, appcast
`docs/appcast.xml`) are **not** part of the CI release workflow yet. To publish
a Sparkle-compatible update:

1. Build and sign the DMG locally using `scripts/release.sh`
   (requires Sparkle CLI `sign_update` and the Ed25519 private key in your
   Keychain).
2. `scripts/release.sh` handles version bump, DMG build, Sparkle signing,
   GitHub Release creation, appcast update, and tag push in one command.

## Manual release (alternative to CI)

For a fully signed, notarized, Sparkle-signed release, run locally:

```
./scripts/release.sh --minor   # or --major / --patch
```

This bumps the version, builds, signs, notarizes, creates the GitHub Release,
updates the appcast, and pushes the tag — all in one go. Requires Xcode,
Developer ID cert, `sign_update`, `create-dmg`, `gh`, and notarization
credentials.
