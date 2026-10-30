# CLI person-property dedupe

Approved follow-up, branch agent/approved-dayflow-followup, based on main64bbe373. Separate from PR59's future-clock probe fix.

Cached properties register once per process (or on genuine value change) as super properties and no longer send person updates on hourly fresh-TTL heartbeats. Fresh probes send person properties once per distinct observed value per process. Opt-out suppresses both sinks and clears publication memory so later opt-in can restore state. No persistent tracking of identity or property-send state.

A pure publication policy has fake-sink XCTest cases for repeated cached heartbeats, relaunch, changed/fresh values, empty properties, opt-out/re-opt-in. Swift/Xcode is unavailable in this Linux environment, so these tests and the app are NOT compiled or run. No real analytics requests. Future-clock/TTL behavior is unchanged, no security/analytics checks removed. No push/PR/CI/native artifact under the no-cost publication hold.
