# CI and hotfix builds

## Routine CI

Pushes to `main` and `koti-batching` run the macOS release build, unit tests, and artifact packaging. Documentation-only changes do not start this runner. If a newer commit arrives on the same branch while a build is queued or running, GitHub cancels the older run so the latest commit gets the runner.

## Urgent build without waiting for unit tests

From **Actions → Build macOS app → Run workflow**, choose the branch containing the hotfix and enable **Skip unit tests for an urgent hotfix artifact build**. The build and packaging still run; the app artifact is available on the workflow run. Leave the box unchecked for the normal full check.

## Hotfix DMG release

For a distributable DMG, update the version and push a `v*` version tag. The **Release macOS DMG** workflow builds the DMG directly from that tag and does not wait for the branch unit-test workflow. This is the fastest release path. Manual release dispatches must also target a `v*` tag; dispatching from a branch is rejected before the build starts.
