## 2026-10-31 - Queue Worker Resilience Against Malformed Parameters

**Vulnerability:** In `dayflow-studio-queue`, batch jobs submitted via `/v1/jobs` were validated for structure and schedule timezones, but the job's primary `timezone` field was not validated. An invalid or non-existent timezone key resulted in an unhandled `ZoneInfoNotFoundError` when the worker loop called `build_request()`, causing repeated worker crashes on the same job and halting queue processing for all clients.

**Learning:** When queue services accept serialized payloads for asynchronous processing, any parameter accessed during job execution without defensive fallback can poison the worker queue if validation at ingress is incomplete.

**Prevention:** Validate all timezone and locale inputs at request intake with `ZoneInfo`, and add defensive fallback in background worker request builders so that corrupt payloads cannot cause persistent worker loop denial of service.
