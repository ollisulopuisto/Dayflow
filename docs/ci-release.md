# CI and hotfix builds

## Routine CI

Pushes to `main` and `koti-batching` run the unit-test suite only. The test command builds the Debug app and test bundle once. Routine pushes do not also build the separate Release app or package an artifact. Documentation-only changes do not start this runner. If a newer commit arrives on the same branch while a build is queued or running, GitHub cancels the older run so the latest commit gets the runner.

## Urgent build without waiting for unit tests

From **Actions → Build macOS app → Run workflow**, choose the branch containing the hotfix. Leave the box unchecked to run tests and build/package a Release artifact, or enable **Skip unit tests for an urgent hotfix artifact build** to build/package without tests. The artifact is available on the workflow run.

## Hotfix DMG release

For a distributable DMG, update the version and push a `v*` version tag. The **Release macOS DMG** workflow builds the DMG directly from that tag and does not wait for the branch unit-test workflow. This is the fastest release path. Manual release dispatches must also target a `v*` tag; dispatching from a branch is rejected before the build starts.

## CodeQL security analysis

GitHub currently runs its separately managed default CodeQL setup for Swift, Python, and Actions. Its Swift job took about 7.5–12.5 minutes on recent runs. The local workflow's documentation filter and concurrency cancellation do not affect those CodeQL runs. Changing their triggers or adding concurrency requires switching CodeQL from default setup to an advanced workflow in the repository's **Settings → Security → Code scanning**; the default setup is not configured by files in this repository.
