## 2026-11-10 - Schedule Window Format Type Validation Preventing Unhandled Request Crashes

**Vulnerability:** In `dayflow-studio-queue`, `/v1/jobs` inspected schedule window fields (`window_start`, `window_end`) by attempting string splitting without asserting their primitive string type. Supplying non-string values (such as integers, nulls, booleans, arrays, or objects) resulted in an unhandled `AttributeError`, bypassing standard HTTP error handling and abruptly terminating request threads.

**Learning:** When string parsing routines like `.split()` are invoked on optional or dictionary-extracted fields with defaults, omitting explicit type checks permits valid non-string JSON primitives and collections to trigger unhandled `AttributeError` exceptions that escape common validation exception tuples (`ValueError`, `KeyError`, `TypeError`).

**Prevention:** Validate primitive types (`isinstance(val, str)`) prior to invoking string manipulation methods on input fields, and include `AttributeError` in top-level request validation exception guards as defense in depth.

## 2026-11-08 - Screenshot Capture Timestamp Relational Range Validation

**Vulnerability:** In `dayflow-studio-queue`, `/v1/jobs` verified screenshot timestamp primitive types (`captured_at`) and parseability via `datetime.fromtimestamp()`, but omitted validating that each capture timestamp was contained within the job's batch time range (`start_ts <= captured_at <= end_ts`). Payloads with out-of-range capture timestamps caused downstream AI timeline prompts with discordant image timestamps, producing cards that failed downstream range checks in `parse_cards()` and triggering repeated job failures.

**Learning:** Verifying individual field types and absolute range boundaries does not guarantee relational consistency between related fields; nested collection items must be bounded by parent or batch scope constraints to prevent poisoned queue jobs from causing downstream validation or processing failures.

**Prevention:** Enforce relational bounds (`start_ts <= shot["captured_at"] <= end_ts`) at API ingress before accepting and persisting queued jobs.

## 2026-11-07 - Ingress Batch Identifier and Payload Structure Validation

**Vulnerability:** In `dayflow-studio-queue`, `/v1/jobs` verified the presence of `batch_id` without verifying its primitive type or range, and accepted arbitrary non-list values for `categories`. Submitting boolean or string-encoded `batch_id` values persisted through processing, but failed downstream deserialization on macOS client poll loops (`result["batch_id"] as? NSNumber`), causing completed jobs to remain unacknowledged and accumulating indefinitely in storage.

**Learning:** When multi-language systems exchange queued jobs across backend services and native clients, permissive ingress validation can allow payloads that pass server-side handling but fail strict type decoding on client runtimes, resulting in orphaned storage state and blocked acknowledgment workflows.

**Prevention:** Validate all identifier types and collection structures strictly (`type(batch_id) is int and batch_id >= 0`, `isinstance(categories, list)`) at API boundaries prior to persistent enqueueing.

## 2026-11-06 - Nested Payload Type and Range Boundary Validation Preventing Queue Poisoning

**Vulnerability:** In `dayflow-studio-queue`, `/v1/jobs` accepted screenshot entries with string-coercible or boolean `captured_at` timestamps via `int()` coercion, as well as timestamps exceeding Python's datetime representation limits. Downstream worker execution crashed with unhandled `TypeError` or `ValueError` in `datetime.fromtimestamp()`, crashing `submit_pending()` and blocking the pending queue.

**Learning:** Using type coercion (`int(val)`) instead of strict type inspection (`type(val) is int`) permits string-encoded integers or booleans into durable storage, which fail downstream when strict integer semantics are required. Furthermore, unbounded integer values can trigger internal limits in standard library date parsing.

**Prevention:** Inspect nested collections strictly for object structure and native primitive types, and test timestamp inputs against datetime conversion boundaries at ingress.

## 2026-11-05 - Ingress Timestamp Type and Range Validation Preventing Queue-Poisoning DoS

**Vulnerability:** In `dayflow-studio-queue`, job submissions on `/v1/jobs` verified the presence of `start_ts` and `end_ts` without asserting that they were integer timestamps or that `start_ts < end_ts`. Submitting non-integer timestamps (e.g. strings or nested structures) was accepted with HTTP 202 and written to the pending queue, causing an unhandled `TypeError` inside `datetime.fromtimestamp()` when the background worker processed the job. Because the unhandled exception crashed `submit_pending()` before updating job state, the malformed job remained at the front of the queue, causing persistent worker loop failure and blocking all subsequent batch processing.

**Learning:** Verifying the mere presence of required fields in an API contract is insufficient for asynchronous queue architectures; type-incompatible fields written to persistent queues can cause persistent head-of-line blocking denial-of-service in downstream workers.

**Prevention:** Strongly validate all primitive types (`isinstance(val, int)`) and relational constraints (`start_ts < end_ts`) at ingress before accepting and queueing background tasks.

## 2026-11-04 - Unvalidated JSON Root Types Leading to Thread-Level Request Crashes

**Vulnerability:** In `dayflow-studio-queue`, `POST` endpoints decoded request bodies using `json.loads` without asserting that the root payload was a JSON object (`dict`). Passing valid JSON primitives or sequences (such as integers, strings, arrays, or booleans) caused unhandled `TypeError` or `AttributeError` during key lookups, terminating request handling threads and abruptly closing client connections without an HTTP error response.

**Learning:** Parsing valid JSON does not guarantee that the resulting Python object conforms to dictionary expectations; missing root-type assertions allow non-object payloads to trigger internal unhandled exceptions before application-level validation occurs.

**Prevention:** Always assert `isinstance(body, dict)` immediately after `json.loads` on JSON endpoints before inspecting dictionary keys or methods.

## 2026-11-01 - Missing Client Identifier Validation Across Queue Service Endpoints

**Vulnerability:** In `dayflow-studio-queue`, queries to `/v1/results` permitted missing or empty `device_id` parameters, resulting in matching any stored results with an empty `device_id` and risking cross-client data leakage. Furthermore, incoming jobs on `/v1/jobs` and acknowledgments on `/v1/ack` did not strictly validate `device_id`, allowing empty or non-alphanumeric identifiers into the queue and authorization checks.

**Learning:** When multi-client services use client-provided identifiers for query isolation or authorization comparisons, omitting strict ingress validation allows degenerate (empty or malformed) identifiers to bypass isolation boundaries.

**Prevention:** Enforce strict format validation (non-empty alphanumeric strings) on client and resource identifiers at all ingress handlers before querying, persisting, or checking authorization.

## 2026-10-31 - Queue Worker Resilience Against Malformed Parameters

**Vulnerability:** In `dayflow-studio-queue`, batch jobs submitted via `/v1/jobs` were validated for structure and schedule timezones, but the job's primary `timezone` field was not validated. An invalid or non-existent timezone key resulted in an unhandled `ZoneInfoNotFoundError` when the worker loop called `build_request()`, causing repeated worker crashes on the same job and halting queue processing for all clients.

**Learning:** When queue services accept serialized payloads for asynchronous processing, any parameter accessed during job execution without defensive fallback can poison the worker queue if validation at ingress is incomplete.

**Prevention:** Validate all timezone and locale inputs at request intake with `ZoneInfo`, and add defensive fallback in background worker request builders so that corrupt payloads cannot cause persistent worker loop denial of service.
