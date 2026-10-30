# Video decoder resource lifecycle investigation

## Observation

On an M2 MacBook with 24 GB RAM, the macOS `VTDecoderXPCService` process was
reported at 6.96 GB while Dayflow was running with capture enabled. The large
decoder entry disappeared after Dayflow was killed; WindowServer memory did not
change. This links the decoder allocation to Dayflow activity but does not prove
a leak or identify the exact feature that opened the decoder.

## Code path

Screen capture obtains a `CGImage` with `SCScreenshotManager.captureImage` and
stores frames in HEVC segments through `AVAssetWriter`. Reading screenshot pixels
later follows `Screenshot.loadCGImage()` into `FrameStore.image()`, which uses an
`AVAssetReaderTrackOutput` to decode the HEVC frame. Timeline previews, playback
frames, analysis, and timelapse generation can all request decoded screenshots.

`FrameStore.shared` retained up to four `SegmentReader` instances in an LRU
cache. Before this change, readers were cancelled only when a reader restarted;
capture stop and app shutdown finalized the writer but left cached readers
retained. This is a plausible reason a VideoToolbox decoder session could remain
alive after frame work ended. It is not confirmed as the source of the 6.96 GB
measurement.

Other video code uses `AVAssetImageGenerator` for movie thumbnails and filmstrips,
and `AVPlayer` for video playback. Those paths are separate from screenshots
stored in HEVC segments. The filmstrip's decoded-image cache is unbounded in app
memory, but it does not by itself explain the large `VTDecoderXPCService`
allocation.

## Speculative change in 2.7.21

- Explicitly cancel a segment reader when its LRU entry is evicted.
- Close all cached readers after 30 seconds without screenshot frame reads.
- Close cached readers when capture stops and when the app is about to terminate.
- Keep the four-reader cache limit and sequential decoding while frames are in
  active use.

## Validation status

`git diff --check` passed. This development environment has Command Line Tools
but no full Xcode installation, so the macOS target could not be built or tested
locally. The tag-triggered GitHub Actions workflow completed successfully for
`v2.7.21` (run [40948327739](https://github.com/ollisulopuisto/Dayflow/actions/runs/40948327739)).
It built the app, created the DMG, and published the release at 2026-10-30
04:38 Europe/Helsinki. The uploaded `Dayflow-2.7.21.dmg` is 104,059,183 bytes
with SHA-256 `5c32728c95cfe662d54dae748fb8e26c88331cf889220081ca1a2f4b2f07f092`.

The build passed, but this does not confirm that the suspected decoder retention
is fixed. Runtime validation on the M2 MacBook remains necessary. Compare decoder
memory, threads, and ports for capture alone, analysis, timeline previews, and
playback; then pause capture and wait beyond the 30-second idle timeout. Repeat
capture and analysis cycles to check for regrowth. No memory bound or release
behavior has yet been confirmed on hardware.

## PR #407 integration follow-up (2026-10-30)

The integration branch ports direct `CMSampleBuffer`/`CVPixelBuffer` capture,
downscaled frame decoding for thumbnails, bounded one-reader caching, and the
PR's explicit cache release paths. The fork's 30-second generation-checked idle
cleanup and delayed launch housekeeping are retained; these avoid decoder churn
during batches and avoid doing the integrity scan on the launch path. First-run
capture remains at the fork's 60-second interval.

The PR's manually managed `NSWindow` lifecycle was not carried over because the
fork uses a SwiftUI `Window` scene. Its memory-purge behavior is adapted to the
fork's controller and runs when the app is hidden/headless. These changes are
code-review findings only at this stage: no build or runtime memory validation
has been performed for this integration branch. Re-run the M2 capture/analysis/
preview/playback cycle above against the resulting build before treating memory
as bounded or the decoder allocation as fixed.
