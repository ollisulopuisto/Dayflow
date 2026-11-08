"""Studio queue tests: window rules, and the gpu-queue job lane against a fake gpu-queue."""

import base64
import importlib
import json
import os
import sys
import tempfile
import threading
import unittest
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from zoneinfo import ZoneInfo

HELSINKI = ZoneInfo("Europe/Helsinki")
NOON = datetime(2026, 10, 15, 12, 0, tzinfo=HELSINKI)
IMAGE = base64.b64encode(b"jpeg-bytes").decode()


def load_server(window_start: str = "01:00", window_end: str = "07:00", gpu_url: str = "http://127.0.0.1:9/v1",
                use_jobs: str = "1", queue_dir: str | None = None):
    os.environ["DAYFLOW_QUEUE_DIR"] = queue_dir or tempfile.mkdtemp(prefix="dayflow-queue-test-")
    os.environ["DAYFLOW_WINDOW_START"] = window_start
    os.environ["DAYFLOW_WINDOW_END"] = window_end
    os.environ["DAYFLOW_TIMEZONE"] = "Europe/Helsinki"
    os.environ["DAYFLOW_GPU_URL"] = gpu_url
    os.environ["DAYFLOW_USE_JOBS"] = use_jobs
    os.environ["DAYFLOW_POLL_SECONDS"] = "0"
    sys.path.insert(0, str(Path(__file__).parent))
    sys.modules.pop("server", None)
    return importlib.import_module("server")


def make_job(job_id: str = "job-1") -> dict:
    return {
        "job_id": job_id, "device_id": "mac", "batch_id": 7,
        "start_ts": 1792015200, "end_ts": 1792015800, "timezone": "Europe/Helsinki",
        "categories": [{"name": "Work", "description": "focused work"}],
        "screenshots": [{"captured_at": 1792015200, "image_base64": IMAGE},
                        {"captured_at": 1792015500, "image_base64": IMAGE}],
    }


def cards_json() -> str:
    cards = [{"start_time": "1:00 AM", "end_time": "1:10 AM", "category": "Work", "subcategory": "Code",
              "title": "Editing", "summary": "Edited files", "detailed_summary": "Edited queue code"}]
    return json.dumps({"cards": cards})


def chat_response(content: str) -> str:
    return json.dumps({"choices": [{"message": {"content": content}}]})


class FakeGpuQueue:
    """Stands in for gpu-queue's dayflow lane: POST /queue/jobs and GET /queue/jobs/<id>."""

    def __init__(self) -> None:
        self.submitted: list[dict] = []
        self.jobs: dict[str, dict] = {}
        self.reject_with: int | None = None
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args: object) -> None:
                pass

            def send_json(self, status: int, value: object) -> None:
                body = json.dumps(value).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length))
                if self.path != "/queue/jobs":
                    return self.send_json(404, {"error": "not found"})
                if fake.reject_with:
                    return self.send_json(fake.reject_with, {"error": "rejected"})
                fake.submitted.append(body)
                job_id = f"gpu-{len(fake.submitted)}"
                fake.jobs[job_id] = {"id": job_id, "status": "pending"}
                return self.send_json(202, {"id": job_id, "status": "pending"})

            def do_GET(self) -> None:
                job_id = self.path.rsplit("/", 1)[-1]
                if job_id not in fake.jobs:
                    return self.send_json(404, {"error": "unknown job"})
                return self.send_json(200, fake.jobs[job_id])

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}/v1"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def finish(self, job_id: str, status: str, **fields: object) -> None:
        self.jobs[job_id] = {"id": job_id, "status": status, **fields}

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()


def write_pending(server, job: dict) -> None:
    (server.PENDING / f"{job['job_id']}.json").write_text(json.dumps(job))


class WindowTests(unittest.TestCase):
    def test_upload_window_is_ignored_during_the_day(self) -> None:
        server = load_server("01:00", "07:00")
        upload = {"window_start": "07:00", "window_end": "01:00", "schedule_timezone": "Europe/Helsinki"}
        self.assertFalse(server.may_process(upload, now=datetime(2026, 10, 15, 10, 0, tzinfo=HELSINKI)))

    def test_server_window_decides_when_upload_has_no_schedule(self) -> None:
        server = load_server("01:00", "07:00")
        self.assertTrue(server.may_process({}, now=datetime(2026, 10, 15, 3, 0, tzinfo=HELSINKI)))
        self.assertFalse(server.may_process({}, now=datetime(2026, 10, 15, 12, 0, tzinfo=HELSINKI)))


class JobLaneTests(unittest.TestCase):
    def setUp(self) -> None:
        self.gpu = FakeGpuQueue()
        self.server = load_server(gpu_url=self.gpu.url)

    def tearDown(self) -> None:
        self.gpu.close()

    def test_batch_is_submitted_as_a_job_at_any_hour(self) -> None:
        write_pending(self.server, make_job())
        self.server.tick(now=NOON)  # daytime: the heavy window must not hold job submission back
        self.assertEqual(len(self.gpu.submitted), 1)
        sent = self.gpu.submitted[0]
        self.assertEqual(sent["path"], "/v1/chat/completions")
        self.assertEqual(sent["request"]["model"], "gemma4-vision")
        self.assertEqual(sent["request"]["chat_template_kwargs"], {"enable_thinking": False})
        self.assertEqual(sum(1 for part in sent["request"]["messages"][0]["content"] if part["type"] == "image_url"), 2)
        self.assertFalse((self.server.PENDING / "job-1.json").exists())
        active = json.loads((self.server.RUNNING / "job-1.json").read_text())
        self.assertEqual(active["gpu_job_id"], "gpu-1")

    def test_pending_gpu_job_keeps_batch_running(self) -> None:
        write_pending(self.server, make_job())
        self.server.tick()
        self.server.tick()  # still pending on gpu-queue
        self.assertEqual(len(self.gpu.submitted), 1)
        self.assertTrue((self.server.RUNNING / "job-1.json").exists())
        self.assertFalse(any(self.server.COMPLETE.glob("*.json")))

    def test_done_job_imports_cards(self) -> None:
        write_pending(self.server, make_job())
        self.server.tick()
        self.gpu.finish("gpu-1", "done", response=chat_response(cards_json()))
        self.server.tick()
        result = json.loads((self.server.COMPLETE / "job-1.json").read_text())
        self.assertEqual(result["cards"][0]["title"], "Editing")
        self.assertFalse((self.server.RUNNING / "job-1.json").exists())

    def test_done_job_accepts_bare_answer_text(self) -> None:
        write_pending(self.server, make_job())
        self.server.tick()
        self.gpu.finish("gpu-1", "done", response=cards_json())
        self.server.tick()
        self.assertTrue((self.server.COMPLETE / "job-1.json").exists())

    def test_model_4xx_failure_is_final(self) -> None:
        write_pending(self.server, make_job())
        self.server.tick()
        self.gpu.finish("gpu-1", "failed", http_status=400, error="bad request", response='{"error":"x"}')
        self.server.tick()
        self.assertTrue((self.server.FAILED / "job-1.json").exists())
        self.assertEqual(len(self.gpu.submitted), 1)

    def test_invalid_cards_are_retried_as_a_new_job(self) -> None:
        write_pending(self.server, make_job())
        self.server.tick()
        self.gpu.finish("gpu-1", "done", response=chat_response('{"cards": "nope"}'))
        self.server.tick()  # bad cards: retried, and the same tick resubmits it as a new gpu job
        self.assertEqual(len(self.gpu.submitted), 2)
        retried = json.loads((self.server.RUNNING / "job-1.json").read_text())
        self.assertEqual(retried["attempts"], 1)
        self.assertEqual(retried["gpu_job_id"], "gpu-2")
        self.assertFalse((self.server.COMPLETE / "job-1.json").exists())

    def test_format_error_gets_one_retry_then_fails(self) -> None:
        write_pending(self.server, make_job())
        self.server.tick()
        self.gpu.finish("gpu-1", "done", response=chat_response('{"cards": []}') .replace("[]", "[{\"start_time\": \"soon\", \"end_time\": \"1:00 AM\", \"category\": \"Work\", \"subcategory\": \"x\", \"title\": \"t\", \"summary\": \"s\", \"detailed_summary\": \"d\"}]"))
        self.server.tick()  # first bad answer: one retry as a new gpu job
        self.assertEqual(len(self.gpu.submitted), 2)
        self.gpu.finish("gpu-2", "done", response=chat_response('{"cards": []}') .replace("[]", "[{\"start_time\": \"soon\", \"end_time\": \"1:00 AM\", \"category\": \"Work\", \"subcategory\": \"x\", \"title\": \"t\", \"summary\": \"s\", \"detailed_summary\": \"d\"}]"))
        self.server.tick()  # second bad answer: the batch stops here
        self.assertTrue((self.server.FAILED / "job-1.json").exists())
        self.assertEqual(len(self.gpu.submitted), 2)

    def test_full_gpu_queue_is_retried_later(self) -> None:
        write_pending(self.server, make_job())
        self.gpu.reject_with = 429
        self.server.tick()
        self.assertTrue((self.server.PENDING / "job-1.json").exists())
        self.assertFalse(any(self.server.RUNNING.glob("*.json")))
        self.gpu.reject_with = None
        self.server.tick()
        self.assertEqual(len(self.gpu.submitted), 1)

    def test_restart_resumes_polling_without_resubmitting(self) -> None:
        write_pending(self.server, make_job())
        self.server.tick()
        # Simulate a restart: the module loads again over the same queue directory.
        restarted = load_server(gpu_url=self.gpu.url, queue_dir=str(self.server.ROOT))
        self.assertTrue((restarted.RUNNING / "job-1.json").exists())
        self.assertFalse((restarted.PENDING / "job-1.json").exists())
        self.gpu.finish("gpu-1", "done", response=chat_response(cards_json()))
        restarted.tick()
        self.assertEqual(len(self.gpu.submitted), 1)
        self.assertTrue((restarted.COMPLETE / "job-1.json").exists())

    def test_crash_between_id_write_and_move_does_not_resubmit(self) -> None:
        job = make_job()
        job["gpu_job_id"] = "gpu-1"
        self.gpu.jobs["gpu-1"] = {"id": "gpu-1", "status": "pending"}
        write_pending(self.server, job)
        self.server.tick()
        self.assertEqual(self.gpu.submitted, [])
        self.assertTrue((self.server.RUNNING / "job-1.json").exists())

    def test_poll_running_skips_json_loads_when_throttled(self) -> None:
        import time
        from unittest.mock import patch
        job = make_job("job-throttled")
        job["gpu_job_id"] = "gpu-throttle-1"
        (self.server.RUNNING / "job-throttled.json").write_text(json.dumps(job))
        # Stamp POLLED_AT to simulate that this job was just polled
        self.server.POLLED_AT["gpu-throttle-1"] = time.monotonic()
        self.server.POLL_SECONDS = 60.0
        with patch("server.json.loads", side_effect=AssertionError("json.loads should not be called when throttled")):
            self.server.poll_running()


class ClockNormalisationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.server = load_server()

    def test_seconds_and_whitespace_are_dropped(self) -> None:
        self.assertEqual(self.server.normalize_clock("1:23:29 AM"), "1:23 AM")
        self.assertEqual(self.server.normalize_clock(" 2:58:01 PM "), "2:58 PM")
        self.assertEqual(self.server.normalize_clock("1:02 pm"), "1:02 PM")

    def test_24_hour_times_are_converted(self) -> None:
        self.assertEqual(self.server.normalize_clock("23:05"), "11:05 PM")
        self.assertEqual(self.server.normalize_clock("00:10"), "12:10 AM")
        self.assertEqual(self.server.normalize_clock("12:00:08 AM"), "12:00 AM")

    def test_dot_separator_is_accepted(self) -> None:
        self.assertEqual(self.server.normalize_clock("11.55"), "11:55 AM")

    def test_garbage_is_rejected(self) -> None:
        self.assertIsNone(self.server.normalize_clock("soon"))
        self.assertIsNone(self.server.normalize_clock("25:00"))
        self.assertIsNone(self.server.normalize_clock("13:00 PM"))


class WatchdogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.server = load_server()

    def test_fresh_heartbeat_is_not_a_stall(self) -> None:
        self.server.LAST_TICK[0] = 1000.0
        self.assertFalse(self.server.worker_stalled(now=1000.0 + self.server.STALL_SECONDS - 1))

    def test_old_heartbeat_is_a_stall(self) -> None:
        self.server.LAST_TICK[0] = 1000.0
        self.assertTrue(self.server.worker_stalled(now=1000.0 + self.server.STALL_SECONDS + 1))

    def test_health_reports_heartbeat_age(self) -> None:
        self.server.LAST_TICK[0] = 0.0
        self.assertGreaterEqual(self.server.heartbeat_age(now=42.0), 42.0)


class PromptTests(unittest.TestCase):
    def test_prompt_asks_for_merged_blocks_not_one_card_per_screenshot(self) -> None:
        server = load_server()
        text = server.build_request(make_job())["messages"][0]["content"][0]["text"]
        self.assertIn("Merge consecutive", text)
        self.assertIn("10 minutes", text)
        self.assertIn("Do not create one card per screenshot", text)

    def test_build_request_falls_back_safely_on_invalid_timezone(self) -> None:
        server = load_server()
        job = make_job()
        job["timezone"] = "Invalid/Bogus_Timezone"
        # Should not raise ZoneInfoNotFoundError
        req = server.build_request(job)
        self.assertIn("messages", req)

    def test_build_request_preserves_image_data_urls(self) -> None:
        server = load_server()
        job = make_job()
        req = server.build_request(job)
        image_parts = [p for p in req["messages"][0]["content"] if p["type"] == "image_url"]
        self.assertEqual(len(image_parts), 2)
        for part in image_parts:
            self.assertEqual(part["image_url"]["url"], f"data:image/jpeg;base64,{IMAGE}")


class EndpointValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.server = load_server()
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), self.server.Handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()

    def test_security_headers_present_on_responses(self) -> None:
        import urllib.request
        req = urllib.request.Request(f"{self.url}/health")
        with urllib.request.urlopen(req) as resp:
            self.assertEqual(resp.headers.get("X-Content-Type-Options"), "nosniff")

    def test_batch_id_and_categories_validation_on_job_submission(self) -> None:
        import urllib.request
        import urllib.error
        # Invalid batch_id cases (non-int, negative int, bool)
        invalid_batch_ids = ["123", True, False, -1, 3.14, None, [1], {"id": 1}]
        for bad_id in invalid_batch_ids:
            bad_job = make_job("bad-batch-id-job")
            bad_job["batch_id"] = bad_id
            req = urllib.request.Request(
                f"{self.url}/v1/jobs",
                data=json.dumps(bad_job).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req)
            self.assertEqual(ctx.exception.code, 400)
            self.assertFalse((self.server.PENDING / "bad-batch-id-job.json").exists())

        # Invalid categories cases (non-list)
        for bad_cats in ("not_a_list", 123, True, {"name": "Work"}):
            bad_job = make_job("bad-cats-job")
            bad_job["categories"] = bad_cats
            req = urllib.request.Request(
                f"{self.url}/v1/jobs",
                data=json.dumps(bad_job).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req)
            self.assertEqual(ctx.exception.code, 400)
            self.assertFalse((self.server.PENDING / "bad-cats-job.json").exists())

    def test_job_submission_with_invalid_timezone_is_rejected(self) -> None:
        import urllib.request
        import urllib.error
        job = make_job("bad-tz-job")
        job["timezone"] = "Invalid/Bogus_Timezone"
        req = urllib.request.Request(
            f"{self.url}/v1/jobs",
            data=json.dumps(job).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req)
        self.assertEqual(ctx.exception.code, 400)
        self.assertFalse((self.server.PENDING / "bad-tz-job.json").exists())

    def test_device_id_validation_on_endpoints(self) -> None:
        import urllib.request
        import urllib.error
        # 1. GET /v1/results requires a valid non-empty alphanumeric/dash device_id
        for bad_path in ("/v1/results", "/v1/results?device_id=", "/v1/results?device_id=../bad/id"):
            req = urllib.request.Request(f"{self.url}{bad_path}")
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req)
            self.assertEqual(ctx.exception.code, 400)

        # 2. POST /v1/jobs rejects missing or invalid device_id
        for bad_device in ("", "mac/../../bad", 12345):
            bad_job = make_job("bad-device-job")
            bad_job["device_id"] = bad_device
            req = urllib.request.Request(
                f"{self.url}/v1/jobs",
                data=json.dumps(bad_job).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req)
            self.assertEqual(ctx.exception.code, 400)

        # 3. POST /v1/ack rejects missing or invalid device_id
        for bad_device in (None, "", "mac/bad"):
            body = {"job_id": "job-1"}
            if bad_device is not None:
                body["device_id"] = bad_device
            req = urllib.request.Request(
                f"{self.url}/v1/ack",
                data=json.dumps(body).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req)
            self.assertEqual(ctx.exception.code, 400)

    def test_ack_rejects_path_traversal_job_id(self) -> None:
        import urllib.error
        import urllib.request
        for bad_job_id in (
            "../../../etc/passwd",
            "../other/secret",
            "/etc/passwd",
            "a/b/c",
        ):
            req = urllib.request.Request(
                f"{self.url}/v1/ack",
                data=json.dumps({"job_id": bad_job_id, "device_id": "mac"}).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req)
            self.assertEqual(ctx.exception.code, 400)
            self.assertFalse((self.server.COMPLETE / f"{bad_job_id}.json").exists())

    def test_oversized_identifiers_rejected(self) -> None:
        import urllib.request
        import urllib.error
        long_id = "a" * 129
        self.assertFalse(self.server.is_valid_identifier(long_id))
        self.assertTrue(self.server.is_valid_identifier("a" * 128))

        # POST /v1/jobs rejects oversized job_id or device_id with 400 (not unhandled OSError)
        bad_job = make_job(long_id)
        req = urllib.request.Request(
            f"{self.url}/v1/jobs",
            data=json.dumps(bad_job).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req)
        self.assertEqual(ctx.exception.code, 400)

        # POST /v1/ack rejects oversized job_id with 400
        req = urllib.request.Request(
            f"{self.url}/v1/ack",
            data=json.dumps({"job_id": long_id, "device_id": "mac"}).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req)
        self.assertEqual(ctx.exception.code, 400)

        # GET /v1/results rejects oversized device_id with 400
        req = urllib.request.Request(f"{self.url}/v1/results?device_id={long_id}")
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req)
        self.assertEqual(ctx.exception.code, 400)

    def test_non_dict_json_payloads_rejected(self) -> None:
        import urllib.request
        import urllib.error
        for payload in (b"123", b'"hello"', b"[1, 2, 3]", b"true"):
            for endpoint in ("/v1/jobs", "/v1/ack"):
                req = urllib.request.Request(
                    f"{self.url}{endpoint}",
                    data=payload,
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                with self.assertRaises(urllib.error.HTTPError) as ctx:
                    urllib.request.urlopen(req)
                self.assertEqual(ctx.exception.code, 400)

    def test_timestamp_validation_on_job_submission(self) -> None:
        import urllib.error
        import urllib.request
        invalid_cases = [
            {"start_ts": "not_int"},
            {"start_ts": None},
            {"start_ts": True},
            {"end_ts": "not_int"},
            {"end_ts": None},
            {"end_ts": False},
            {"start_ts": 1792015800, "end_ts": 1792015200},  # end_ts < start_ts
            {"start_ts": 1792015200, "end_ts": 1792015200},  # end_ts == start_ts
            {"start_ts": 10**14, "end_ts": 10**14 + 100},  # timestamp out of bounds
        ]
        for case in invalid_cases:
            bad_job = make_job("bad-timestamp-job")
            bad_job.update(case)
            req = urllib.request.Request(
                f"{self.url}/v1/jobs",
                data=json.dumps(bad_job).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req)
            self.assertEqual(ctx.exception.code, 400)
            self.assertFalse((self.server.PENDING / "bad-timestamp-job.json").exists())

    def test_screenshot_payload_validation_on_job_submission(self) -> None:
        import urllib.error
        import urllib.request
        invalid_screenshots = [
            "not_a_dict",
            {"image_base64": IMAGE, "captured_at": "1792015200"},  # string timestamp
            {"image_base64": IMAGE, "captured_at": True},  # bool timestamp
            {"image_base64": 12345, "captured_at": 1792015200},  # non-string image_base64
            {"image_base64": IMAGE, "captured_at": 10**14},  # timestamp out of bounds
        ]
        for bad_shot in invalid_screenshots:
            bad_job = make_job("bad-shot-job")
            bad_job["screenshots"] = [bad_shot]
            req = urllib.request.Request(
                f"{self.url}/v1/jobs",
                data=json.dumps(bad_job).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(req)
            self.assertEqual(ctx.exception.code, 400)
            self.assertFalse((self.server.PENDING / "bad-shot-job.json").exists())


class AuthTests(unittest.TestCase):
    def setUp(self) -> None:
        self.server = load_server()
        self.server.TOKEN = "s3cret-token"

    def test_exact_bearer_token_is_accepted(self) -> None:
        self.assertTrue(self.server.token_matches("Bearer s3cret-token"))

    def test_trailing_newline_from_a_copied_token_is_tolerated(self) -> None:
        self.assertTrue(self.server.token_matches("Bearer s3cret-token\n"))
        self.assertTrue(self.server.token_matches("Bearer  s3cret-token "))

    def test_wrong_or_missing_token_is_rejected(self) -> None:
        self.assertFalse(self.server.token_matches("Bearer wrong"))
        self.assertFalse(self.server.token_matches("s3cret-token"))
        self.assertFalse(self.server.token_matches(None))


class SyncFallbackTests(unittest.TestCase):
    def test_flag_off_never_touches_the_job_lane(self) -> None:
        gpu = FakeGpuQueue()
        try:
            server = load_server("01:00", "07:00", gpu_url=gpu.url, use_jobs="0")
            write_pending(server, make_job())
            server.tick(now=NOON)  # outside the window: the synchronous path waits
            self.assertEqual(gpu.submitted, [])
            self.assertTrue((server.PENDING / "job-1.json").exists())
        finally:
            gpu.close()


if __name__ == "__main__":
    unittest.main()
