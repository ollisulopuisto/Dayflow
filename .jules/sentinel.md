## 2026-11-01 - Missing Client Identifier Validation Across Queue Service Endpoints

**Vulnerability:** In `dayflow-studio-queue`, queries to `/v1/results` permitted missing or empty `device_id` parameters, resulting in matching any stored results with an empty `device_id` and risking cross-client data leakage. Furthermore, incoming jobs on `/v1/jobs` and acknowledgments on `/v1/ack` did not strictly validate `device_id`, allowing empty or non-alphanumeric identifiers into the queue and authorization checks.

**Learning:** When multi-client services use client-provided identifiers for query isolation or authorization comparisons, omitting strict ingress validation allows degenerate (empty or malformed) identifiers to bypass isolation boundaries.

**Prevention:** Enforce strict format validation (non-empty alphanumeric strings) on client and resource identifiers at all ingress handlers before querying, persisting, or checking authorization.

## 2026-10-31 - Queue Worker Resilience Against Malformed Parameters

**Vulnerability:** In `dayflow-studio-queue`, batch jobs submitted via `/v1/jobs` were validated for structure and schedule timezones, but the job's primary `timezone` field was not validated. An invalid or non-existent timezone key resulted in an unhandled `ZoneInfoNotFoundError` when the worker loop called `build_request()`, causing repeated worker crashes on the same job and halting queue processing for all clients.

**Learning:** When queue services accept serialized payloads for asynchronous processing, any parameter accessed during job execution without defensive fallback can poison the worker queue if validation at ingress is incomplete.

**Prevention:** Validate all timezone and locale inputs at request intake with `ZoneInfo`, and add defensive fallback in background worker request builders so that corrupt payloads cannot cause persistent worker loop denial of service.
