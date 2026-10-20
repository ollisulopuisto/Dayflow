1. Fix the bug identified in code review:
   - Restore the fallback logic in `screenshots(for:)`. If `timelineCard` bounds yield no screenshots, we need to try the `activity`'s bounds.
   - Prevent the fallback DB query when the cache already proves there are no screenshots in the requested range.
