# Bolt's Journal

Critical learnings only.

## 2026-11-02 - Studio Queue Card Parsing and Clock Normalization
**Learning:** `server.parse_cards` performed redundant passes over model response cards: validating presence of fields in one loop, parsing and normalizing timestamps with dynamic regex compilation in another, and then redundant `re.fullmatch` and `datetime.strptime` checks in a third pass over already-normalized timestamps. Pre-compiling `CLOCK_RE` and consolidating field validation, normalization, and allowed categories verification into a single loop reduced batch card processing time by ~72% (3.57x speedup).
**Action:** In data ingestion/queue services handling model responses, compile regex at module scope and validate/normalize structured payloads in a single pass rather than multiple sequential loops.

## 2026-11-04 - Studio Queue Vision Request Payload Redundant Base64 Round-trips
**Learning:** `server.build_request` in `tools/dayflow-studio-queue` was redundantly base64-decoding and re-encoding pre-validated screenshot strings (`image_base64`) into `data:image/jpeg;base64,` URLs for each frame in a batch. For a standard 15-frame batch, this decode/encode churn consumed ~18.5 ms per batch. Interpolating the existing validated base64 string directly into the data URI dropped request construction latency from 20.72 ms to 2.18 ms (9.49x speedup, ~89.5% reduction) without modifying output format or semantics.
**Action:** In proxy or queue services forwarding base64 image payloads to vision endpoints, avoid decode/encode roundtripping if the string format is already validated at ingestion.

## 2026-11-05 - Studio Queue Ingestion Write Redundant JSON Serialization
**Learning:** In `Handler.do_POST` for `/v1/jobs` in `tools/dayflow-studio-queue/server.py`, incoming multipart batch payloads (~5–15 MB of base64 screenshot data) were parsed from raw network bytes into a dictionary with `json.loads` for validation, but then re-serialized with `json.dumps(body, ...)` prior to writing to the pending spool directory. Writing the validated raw request bytes directly to disk via `temp.write_bytes(raw_body)` avoids re-serializing multi-megabyte payloads, dropping `/v1/jobs` mean response time from 223.24 ms to 141.53 ms (1.58x speedup, 36.6% latency reduction) and eliminating large transient heap allocations.
**Action:** In HTTP ingestion endpoints that persist raw payloads after schema/integrity validation, write the raw incoming bytes directly to disk rather than re-serializing the validated in-memory dictionary.

## 2026-11-06 - Studio Queue Results Polling and JSON Deserialization Filtering
**Learning:** In `Handler.do_GET` for `/v1/results` in `tools/dayflow-studio-queue/server.py`, polling for a client device's completed jobs used `COMPLETE.glob("*.json")` and unconditionally parsed every completed job file with `json.loads(result_file.read_text())` regardless of which device owned the job. Switching directory iteration to `os.scandir` and pre-filtering raw bytes for the target `device_id` needle prior to `json.loads` avoids unneeded JSON deserialization of non-matching completed jobs, reducing query scanning time by 52.7% (2.12x speedup from 5.91 ms to 2.79 ms for 100 jobs) and end-to-end polling latency from 8.53 ms to 5.16 ms per request.
**Action:** In file-backed queue querying endpoints where filtering by client ID occurs over completed files, avoid instantiating Path objects and pre-filter raw file bytes before executing full JSON deserialization.

## 2026-11-07 - Studio Queue Redundant Screenshot Timestamp Formatting in Request Builder
**Learning:** In `server.build_request` in `tools/dayflow-studio-queue/server.py`, screenshot capture timestamps were formatted with `datetime.fromtimestamp(s['captured_at'], local_zone).strftime('%-I:%M:%S %p')` twice per frame: once when constructing the prompt instruction header (`Image timestamps in order: ...`) and again when building individual content message segments (`Capture at ...`). Precomputing formatted timestamps once into a list and iterating with `zip` eliminated 15 redundant datetime creations and strftime invocations per 15-frame batch, reducing `build_request` latency from 0.210 ms to 0.121 ms (1.73x speedup, 42.1% reduction).
**Action:** When building composite prompt templates and itemized content messages from the same list of timestamped artifacts, precompute formatted string representations once rather than formatting repeatedly in separate loops.
