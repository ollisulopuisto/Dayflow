# CLI probe cache: wall-clock rollback

Follow-through on the persisted CLI-probe TTL in `docs/PERFORMANCE.md`, startup
item8. Current main already persists the timestamp and last-known properties;
that work must not be implemented again.

A remaining boundary case: if the persisted timestamp is later than the current
clock, `now - lastRefresh` is negative and the existing24-hour check suppresses
probes until that future timestamp plus24hours. This can follow a system-clock
correction. Treat negative age as stale, while exactly-now remains fresh.
A successful refresh writes the current timestamp, so it does not continually
re-probe. Analytics opt-in checks and probe scope are unchanged.

Branch: `overnight/cli-probe-clock-rollback`, based on64bbe37.

## Verification

Added XCTest coverage for timestamps one hour and seven days ahead, plus
exactly-now. Existing TTL boundary tests retained. Diff whitespace check passes.
No Swift compiler or Xcode is available here, so XCTest and native compilation
remain unrun. This is a reviewable source fix, not a tested Mac build or measured
performance improvement. No workflow was dispatched and no GitHub charges were
incurred. Existing Mac workflow/storage route remains held under zero-new-cost
instruction. No merge, tag or release.
