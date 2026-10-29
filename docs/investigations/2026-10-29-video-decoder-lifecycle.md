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
locally. The DMG's tag-triggered GitHub Actions workflow is expected to perform
the release build.

Runtime validation on the M2 MacBook remains necessary. Compare decoder memory,
threads, and ports for capture alone, analysis, timeline previews, and playback;
then pause capture and wait beyond the 30-second idle timeout. Repeat capture
and analysis cycles to check for regrowth. No memory bound or release behavior
has yet been confirmed on hardware.
