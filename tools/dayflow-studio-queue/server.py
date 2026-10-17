#!/usr/bin/env python3
"""Small durable queue for Dayflow batches on an always-on Mac Studio."""

from __future__ import annotations

import base64
import hmac
import json
import os
import re
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

ROOT = Path(os.environ.get("DAYFLOW_QUEUE_DIR", "~/Library/Application Support/dayflow-studio-queue")).expanduser()
PENDING = ROOT / "pending"
RUNNING = ROOT / "running"
COMPLETE = ROOT / "complete"
FAILED = ROOT / "failed"
TOKEN = os.environ.get("DAYFLOW_QUEUE_TOKEN", "")
HOST = os.environ.get("DAYFLOW_QUEUE_HOST", "0.0.0.0")
PORT = int(os.environ.get("DAYFLOW_QUEUE_PORT", "8765"))
GPU_URL = os.environ.get("DAYFLOW_GPU_URL", "http://127.0.0.1:8104/v1").rstrip("/")
GPU_BASE = GPU_URL[:-3] if GPU_URL.endswith("/v1") else GPU_URL
# Default on: gpu-queue's job lane decides when a batch runs (its heavy window, priorities).
# Set DAYFLOW_USE_JOBS=0 to roll back to the synchronous path, which waits for its own window.
USE_JOBS = os.environ.get("DAYFLOW_USE_JOBS", "1") == "1"
POLL_SECONDS = float(os.environ.get("DAYFLOW_POLL_SECONDS", "60"))
MODEL = os.environ.get("DAYFLOW_MODEL", "gemma4-vision")
TIMEZONE = os.environ.get("DAYFLOW_TIMEZONE", "Europe/Helsinki")
WINDOW_START = os.environ.get("DAYFLOW_WINDOW_START", "07:00")
WINDOW_END = os.environ.get("DAYFLOW_WINDOW_END", "01:00")
MAX_TOKENS = int(os.environ.get("DAYFLOW_MAX_TOKENS", "4096"))
WORKER_LOCK = threading.Lock()
POLLED_AT: dict[str, float] = {}
PARSE_ATTEMPTS = 2
# The worker stamps LAST_TICK on every loop. If it stops stamping (a hung HTTP call or a lost
# thread), the watchdog exits the process and launchd (KeepAlive) starts it again.
STALL_SECONDS = float(os.environ.get("DAYFLOW_STALL_SECONDS", "600"))
LAST_TICK = [time.monotonic()]

for folder in (PENDING, RUNNING, COMPLETE, FAILED):
    folder.mkdir(parents=True, exist_ok=True)

def requeue_unfinished() -> None:
    # Jobs left in running after a crash go back to pending, except those already submitted
    # to gpu-queue: those resume polling their gpu job id instead of being submitted twice.
    for job_file in RUNNING.glob("*.json"):
        try:
            job = json.loads(job_file.read_text())
        except ValueError:
            job = {}
        if USE_JOBS and job.get("gpu_job_id"):
            continue
        job_file.replace(PENDING / job_file.name)


requeue_unfinished()


def token_matches(header: Optional[str]) -> bool:
    # Surrounding whitespace is stripped from the presented token: a token copied with a
    # trailing newline must not lock the app out. The comparison itself is constant-time.
    if header is None or not header.startswith("Bearer "):
        return False
    presented = header[len("Bearer "):].strip()
    return hmac.compare_digest(presented.encode(), TOKEN.encode())


def authorized(handler: BaseHTTPRequestHandler) -> bool:
    if not TOKEN:
        return True
    return token_matches(handler.headers.get("Authorization"))


def in_window(zone_name: str = TIMEZONE, start_text: str = WINDOW_START,
              end_text: str = WINDOW_END, now: Optional[datetime] = None) -> bool:
    current = now or datetime.now(ZoneInfo(zone_name))
    minute = current.hour * 60 + current.minute
    start_h, start_m = map(int, start_text.split(":"))
    end_h, end_m = map(int, end_text.split(":"))
    start, end = start_h * 60 + start_m, end_h * 60 + end_m
    if start == end:
        return True
    if start < end:
        return start <= minute < end
    return minute >= start or minute < end


def build_request(job: dict) -> dict:
    local_zone = ZoneInfo(job.get("timezone") or TIMEZONE)
    screenshots = sorted(job["screenshots"], key=lambda shot: shot["captured_at"])
    content: list[dict] = [{
        "type": "text",
        "text": (
            "Create Dayflow timeline activity cards from these ordered screen captures. "
            "Return only a JSON object with a `cards` array. Each card must have "
            "start_time and end_time as local clock strings formatted h:mm AM/PM, "
            "category, subcategory, title, summary, and detailed_summary. "
            "Merge consecutive frames showing the same activity into one card; a card should cover "
            "at least 10 minutes, ideally about 15, and no card may be shorter than 5 minutes. "
            "Do not create one card per screenshot. "
            "Use concise factual descriptions, do not infer unseen activity, and cover "
            "only work supported by the images. The batch spans "
            f"{datetime.fromtimestamp(job['start_ts'], local_zone).isoformat()} through "
            f"{datetime.fromtimestamp(job['end_ts'], local_zone).isoformat()}. "
            "Choose category from this configured list and use its name exactly: "
            + json.dumps(job.get("categories", []), ensure_ascii=False)
            + ". Use the closest fit from this list; do not invent a category. "
            + "Image timestamps in order: " + ", ".join(
                datetime.fromtimestamp(s["captured_at"], local_zone).strftime("%-I:%M:%S %p")
                for s in screenshots
            )
        ),
    }]
    for shot in screenshots:
        image_bytes = base64.b64decode(shot["image_base64"])
        content.append({"type": "text", "text": f"Capture at {datetime.fromtimestamp(shot['captured_at'], local_zone).strftime('%-I:%M:%S %p')}"})
        content.append({"type": "image_url", "image_url": {
            "url": "data:image/jpeg;base64," + base64.b64encode(image_bytes).decode("ascii")
        }})
    return {
        "model": MODEL,
        "messages": [{"role": "user", "content": content}],
        "temperature": 0.2,
        "max_tokens": MAX_TOKENS,
        "chat_template_kwargs": {"enable_thinking": False},
        "response_format": {"type": "json_object"},
    }


def analyze(job: dict) -> list[dict]:
    # Synchronous path (DAYFLOW_USE_JOBS=0): one blocking call to gpu-queue's chat endpoint.
    request = urllib.request.Request(
        f"{GPU_URL}/chat/completions", data=json.dumps(build_request(job)).encode(),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    with urllib.request.urlopen(request, timeout=1800) as response:
        answer = json.load(response)["choices"][0]["message"]["content"]
    return parse_cards(answer, job)


def normalize_clock(value: str) -> Optional[str]:
    # The model writes h:mm, h:mm:ss, 24-hour or dotted times. Dayflow stores h:mm AM/PM.
    match = re.fullmatch(r"\s*(\d{1,2})[:.](\d{2})(?::\d{2})?\s*([AaPp])?\s*[Mm]?\s*", value)
    if not match:
        return None
    hour, minute = int(match.group(1)), int(match.group(2))
    suffix = match.group(3)
    if minute > 59:
        return None
    if suffix:
        if not 1 <= hour <= 12:
            return None
        hour24 = hour % 12 + (12 if suffix.lower() == "p" else 0)
    else:
        if hour > 23:
            return None
        hour24 = hour
    return f"{hour24 % 12 or 12}:{minute:02d} {'AM' if hour24 < 12 else 'PM'}"


def parse_cards(answer: str, job: dict) -> list[dict]:
    parsed = json.loads(answer)
    cards = parsed.get("cards") if isinstance(parsed, dict) else None
    if not isinstance(cards, list):
        raise ValueError("Model response did not contain a cards array")
    required = ("start_time", "end_time", "category", "subcategory", "title", "summary", "detailed_summary")
    if any(not isinstance(card, dict) or any(not isinstance(card.get(k), str) for k in required) for card in cards):
        raise ValueError("Model returned a card with missing or invalid fields")
    for card in cards:
        for key in ("start_time", "end_time"):
            normalised = normalize_clock(card[key])
            if normalised is None:
                raise ValueError("Model returned a timestamp outside h:mm AM/PM format")
            card[key] = normalised
    allowed_categories = {category.get("name") for category in job.get("categories", [])}
    for card in cards:
        for key in ("start_time", "end_time"):
            if not re.fullmatch(r"\d{1,2}:\d{2} [AP]M", card[key]):
                raise ValueError("Model returned a timestamp outside h:mm AM/PM format")
            datetime.strptime(card[key], "%I:%M %p")
        if allowed_categories and card["category"] not in allowed_categories:
            raise ValueError("Model returned a category not present in Dayflow settings")
    return cards


def may_process(upload_schedule: dict, now: Optional[datetime] = None) -> bool:
    # The server's own environment decides when work runs. The schedule a laptop sends with
    # a job is ignored, so a client can never open a window that gpu-queue refuses.
    del upload_schedule
    return in_window(TIMEZONE, WINDOW_START, WINDOW_END, now)


def heartbeat_age(now: Optional[float] = None) -> float:
    return (now if now is not None else time.monotonic()) - LAST_TICK[0]


def worker_stalled(now: Optional[float] = None, limit: Optional[float] = None) -> bool:
    return heartbeat_age(now) > (limit if limit is not None else STALL_SECONDS)


def watchdog() -> None:
    while True:
        time.sleep(30)
        if worker_stalled():
            print(f"Worker stalled for {heartbeat_age():.0f}s; exiting so launchd restarts the service", flush=True)
            os._exit(3)


def write_json(path: Path, value: dict) -> None:
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(value, separators=(",", ":")))
    temp.replace(path)


def gpu_call(method: str, path: str, body: Optional[dict] = None) -> Optional[dict]:
    # Returns None when gpu-queue says its lane is full (429); other HTTP errors are raised.
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(f"{GPU_BASE}{path}", data=data,
                                     headers={"Content-Type": "application/json"}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 429:
            return None
        raise


def job_answer(status: dict) -> str:
    # gpu-queue returns the model's raw response text: a chat completion, or the bare answer.
    text = status["response"]
    body = json.loads(text)
    if isinstance(body, dict) and "choices" in body:
        return body["choices"][0]["message"]["content"]
    return text


def retry_or_fail(active: Path, job: dict, error: str, max_attempts: int = 5) -> None:
    # A new gpu-queue job is submitted on retry, so the stale gpu job id is dropped.
    job.pop("gpu_job_id", None)
    job["error"] = error
    job["attempts"] = int(job.get("attempts", 0)) + 1
    write_json((PENDING if job["attempts"] < max_attempts else FAILED) / active.name, job)
    active.unlink(missing_ok=True)


def fail_job(path: Path, job: dict, error: str) -> None:
    job["error"] = error
    write_json(FAILED / path.name, job)
    path.unlink(missing_ok=True)


def submit_pending() -> None:
    for source in sorted(PENDING.glob("*.json"), key=lambda path: path.stat().st_mtime):
        try:
            job = json.loads(source.read_text())
        except (OSError, ValueError):
            continue
        if not job.get("gpu_job_id"):
            print(f"Submitting {job.get('job_id')} to gpu-queue", flush=True)
            try:
                reply = gpu_call("POST", "/queue/jobs", {"path": "/v1/chat/completions", "request": build_request(job)})
            except urllib.error.HTTPError as error:
                if error.code in (400, 413):
                    fail_job(source, job, f"gpu-queue rejected the job: HTTP {error.code}")
                    continue
                return
            except OSError as error:
                print(f"gpu-queue unreachable, will retry: {error}", flush=True)
                return
            if reply is None:
                return  # lane full: try again on the next tick
            # Store the gpu job id before moving the file, so a crash cannot submit it twice.
            job["gpu_job_id"] = reply["id"]
            write_json(source, job)
        source.replace(RUNNING / source.name)


def poll_running() -> None:
    for active in sorted(RUNNING.glob("*.json")):
        try:
            job = json.loads(active.read_text())
        except (OSError, ValueError):
            continue
        gpu_id = job.get("gpu_job_id")
        if not gpu_id:
            continue
        if time.monotonic() - POLLED_AT.get(gpu_id, 0.0) < POLL_SECONDS:
            continue
        POLLED_AT[gpu_id] = time.monotonic()
        try:
            status = gpu_call("GET", f"/queue/jobs/{gpu_id}")
        except urllib.error.HTTPError as error:
            if error.code == 404:
                retry_or_fail(active, job, "gpu-queue no longer knows this job")
            continue
        except OSError:
            continue  # unreachable: poll again next time
        if status is None:
            continue
        state = status.get("status")
        if state == "done":
            try:
                cards = parse_cards(job_answer(status), job)
            except Exception as error:
                # A wrong answer format usually comes back the same way, so one retry is enough.
                retry_or_fail(active, job, str(error), max_attempts=PARSE_ATTEMPTS)
                continue
            result = {
                "job_id": job["job_id"], "device_id": job["device_id"],
                "batch_id": job["batch_id"], "cards": cards,
                "completed_at": datetime.now().astimezone().isoformat(),
            }
            write_json(COMPLETE / active.name, result)
            active.unlink(missing_ok=True)
            print(f"Completed {job['job_id']}", flush=True)
        elif state == "failed":
            fail_job(active, job, status.get("error") or f"gpu-queue job failed (HTTP {status.get('http_status')})")
            print(f"Failed {job['job_id']}: {job['error']}", flush=True)


def sync_tick() -> None:
    jobs = sorted(PENDING.glob("*.json"), key=lambda path: path.stat().st_mtime)
    if not jobs:
        return
    source = jobs[0]
    active = RUNNING / source.name
    try:
        source.replace(active)
        job = json.loads(active.read_text())
        result = {
            "job_id": job["job_id"], "device_id": job["device_id"],
            "batch_id": job["batch_id"], "cards": analyze(job),
            "completed_at": datetime.now().astimezone().isoformat(),
        }
        write_json(COMPLETE / source.name, result)
        active.unlink(missing_ok=True)
        print(f"Completed {job['job_id']}", flush=True)
    except Exception as error:
        try:
            retry_or_fail(active, json.loads(active.read_text()), str(error))
        except Exception:
            print(f"Could not recover job {active.name}: {error}", flush=True)
        print(f"Processing failed: {error}", flush=True)


def tick(now: Optional[datetime] = None) -> None:
    if not USE_JOBS:
        if may_process({}, now):
            sync_tick()
        return
    # Job lane: gpu-queue decides when a batch runs, so this side never checks a window.
    poll_running()
    submit_pending()


def worker() -> None:
    while True:
        time.sleep(20)
        LAST_TICK[0] = time.monotonic()
        if not WORKER_LOCK.acquire(blocking=False):
            continue
        try:
            tick()
        except Exception as error:
            print(f"Worker error: {error}", flush=True)
        finally:
            WORKER_LOCK.release()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        print("dayflow-queue: " + format % args, flush=True)

    def respond(self, status: int, value: object) -> None:
        body = json.dumps(value, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if not authorized(self):
            return self.respond(401, {"error": "unauthorized"})
        if self.path == "/health":
            return self.respond(200, {"ok": True, "in_window": in_window(), "pending": len(list(PENDING.glob("*.json"))),
                                      "heartbeat_age_s": round(heartbeat_age(), 1)})
        if self.path.startswith("/v1/results"):
            from urllib.parse import parse_qs, urlparse
            device_id = parse_qs(urlparse(self.path).query).get("device_id", [""])[0]
            results = []
            for result_file in COMPLETE.glob("*.json"):
                try:
                    result = json.loads(result_file.read_text())
                    if result.get("device_id") == device_id:
                        results.append(result)
                except (OSError, json.JSONDecodeError):
                    continue
            return self.respond(200, results)
        self.respond(404, {"error": "not found"})

    def do_POST(self) -> None:
        if not authorized(self):
            return self.respond(401, {"error": "unauthorized"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 100_000_000:
                return self.respond(413, {"error": "invalid body size"})
            body = json.loads(self.rfile.read(length))
        except (ValueError, json.JSONDecodeError):
            return self.respond(400, {"error": "invalid JSON"})
        if self.path == "/v1/jobs":
            required = ("job_id", "device_id", "batch_id", "start_ts", "end_ts", "timezone", "screenshots")
            if any(key not in body for key in required) or not isinstance(body["screenshots"], list):
                return self.respond(400, {"error": "missing job fields"})
            if not body["screenshots"] or len(body["screenshots"]) > 15:
                return self.respond(400, {"error": "a job must contain 1 to 15 screenshots"})
            try:
                ZoneInfo(body.get("schedule_timezone", TIMEZONE))
                for key in ("window_start", "window_end"):
                    hour, minute = map(int, body.get(key, "07:00").split(":"))
                    if hour not in range(24) or minute not in range(60):
                        raise ValueError("invalid time")
                for shot in body["screenshots"]:
                    base64.b64decode(shot["image_base64"], validate=True)
                    int(shot["captured_at"])
            except (ValueError, KeyError, TypeError, ZoneInfoNotFoundError):
                return self.respond(400, {"error": "invalid screenshot or processing schedule"})
            name = str(body["job_id"])
            if not name.replace("-", "").isalnum():
                return self.respond(400, {"error": "invalid job id"})
            if (COMPLETE / f"{name}.json").exists() or (PENDING / f"{name}.json").exists() or (RUNNING / f"{name}.json").exists():
                return self.respond(200, {"accepted": True, "duplicate": True})
            path = PENDING / f"{name}.json"
            temp = PENDING / f"{name}.tmp"
            temp.write_text(json.dumps(body, separators=(",", ":")))
            temp.replace(path)
            return self.respond(202, {"accepted": True})
        if self.path == "/v1/ack":
            job_id = str(body.get("job_id", ""))
            if not job_id.replace("-", "").isalnum():
                return self.respond(400, {"error": "invalid job id"})
            result = COMPLETE / f"{job_id}.json"
            if result.exists():
                try:
                    value = json.loads(result.read_text())
                    if value.get("device_id") != body.get("device_id"):
                        return self.respond(403, {"error": "job belongs to another device"})
                    result.unlink()
                except (OSError, json.JSONDecodeError):
                    return self.respond(500, {"error": "could not acknowledge job"})
            return self.respond(200, {"acknowledged": True})
        self.respond(404, {"error": "not found"})


if __name__ == "__main__":
    if not TOKEN:
        raise SystemExit("Set DAYFLOW_QUEUE_TOKEN to a long random secret before starting the service")
    threading.Thread(target=worker, daemon=True, name="dayflow-worker").start()
    threading.Thread(target=watchdog, daemon=True, name="dayflow-watchdog").start()
    print(f"Dayflow queue listening on {HOST}:{PORT}; GPU endpoint {GPU_URL}; hours {WINDOW_START}-{WINDOW_END} {TIMEZONE}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
