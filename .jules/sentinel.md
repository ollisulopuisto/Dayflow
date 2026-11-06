## 2026-11-06 - CLI Dynamic Argument Shell Sanitization Preventing Command Injection

**Vulnerability:** In `ChatCLIProcessRunner`, dynamic CLI arguments including `model`, `reasoningEffort`, and `sessionId` are joined into shell commands executed via login shell (`bash -l -i -c`). Without shell escaping, unvalidated or model-provided arguments containing shell metacharacters (e.g. `;`, `&&`, `'`, `$()`) allow arbitrary command execution.

**Learning:** When passing dynamic arguments through an interactive login shell invocation (`-c "<cmd>"`), array-based flags must still be escaped using POSIX single-quote wrapping (`LoginShellRunner.shellEscape`) before string concatenation.

**Prevention:** Ensure all dynamic CLI arguments (models, session IDs, reasoning efforts, custom overrides, and paths) are sanitized through `LoginShellRunner.shellEscape(_:)` before inclusion in command lines.

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
