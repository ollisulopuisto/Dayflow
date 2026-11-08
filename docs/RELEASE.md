# Release Process

Dayflow releases are produced automatically by GitHub Actions. Pushing a tag
matching `v*` (e.g. `v2.7.8`) to this repository triggers the
[release workflow](../.github/workflows/release.yml), which:

1. Builds the app with Xcode (Release configuration)
2. Codesigns it with the required Developer ID certificate
3. Creates a signed DMG with `create-dmg`
4. Notarizes the DMG with the required Apple credentials, staples its ticket, and checks Gatekeeper
5. Creates a GitHub Release and uploads the versioned arm64 DMG and SHA-256 sidecar
6. Optionally uploads dSYMs to Sentry for crash symbolication

## Making a release

1. Bump the version in `Dayflow/Dayflow.xcodeproj/project.pbxproj`
   (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`) and in
   `Dayflow/Dayflow/Info.plist` (`CFBundleShortVersionString` and
   `CFBundleVersion`).
2. Add a `## [X.Y.Z] - YYYY-MM-DD` entry to `CHANGELOG.md` and copy it to
   `Dayflow/Dayflow/CHANGELOG.md` for the bundled What's New. Update the release
   metadata contract in `scripts/ci/test_upstream_merge_contract.py`.
3. Open a PR for the changes, wait for checks, and have the owner merge it.
   Build releases from the latest merged main. Example commit:
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
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` certificate for team `LWSR8T5392` | Yes |
| `P12_PASSWORD` | Password for the `.p12` | Yes |
| `KEYCHAIN_PASSWORD` | Password for the disposable CI signing keychain | Yes |
| `NOTARY_APPLE_ID` or `APPLE_ID` | Apple ID for notarization (NOTARY name wins) | Yes, one |
| `NOTARY_APP_PASSWORD` or `APPLE_APP_PASSWORD` | App-specific password (NOTARY name wins) | Yes, one |
| `NOTARY_TEAM_ID` | Apple Developer Team ID | No, defaults to `LWSR8T5392` |
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
`BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, and `KEYCHAIN_PASSWORD` are set).

### Setting up notarization

The CI workflow creates its own temporary keychain profile. Provide the Apple ID
and app-specific password secrets listed above. A local profile is not available
on a fresh GitHub runner. Passwords reach keychain tools over stdin or a private,
echo-disabled TTY, never process arguments; submit/log use the stored profile.

Missing signing or notarization credentials fail the release before publication.
There is no unsigned or unnotarized release fallback. A local unsigned compile is
still available via `scripts/build_local.sh --unsigned` and is not a release.

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

## Private manual builds

Dispatch `Release macOS DMG` on merged `main` for an unpublished draft. It uses
the same required signing, notarization and checksum gates as a tagged release,
but creates no public version tag or public release and never marks itself latest.
Downloads include version, manual run number and arm64 architecture. Only the repository owner may dispatch or rerun this manual route. Draft GitHub
links require repository write access: GitHub drafts are not a per-person privacy
boundary, so any collaborators with write access can also see them. No Actions artifacts or caches are uploaded.
Existing version-tag release behavior is unchanged.
