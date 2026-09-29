#!/usr/bin/env python3
"""Small durable queue for Dayflow batches on an always-on Mac Studio."""

from __future__ import annotations

import base64
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
GPU_URL = os.environ.get("DAYFLOW_GPU_URL", "http://127.0.0.1:8103/v1").rstrip("/")
MODEL = os.environ.get("DAYFLOW_MODEL", "gemma4-vision")
TIMEZONE = os.environ.get("DAYFLOW_TIMEZONE", "Europe/Helsinki")
WINDOW_START = os.environ.get("DAYFLOW_WINDOW_START", "07:00")
WINDOW_END = os.environ.get("DAYFLOW_WINDOW_END", "01:00")
MAX_TOKENS = int(os.environ.get("DAYFLOW_MAX_TOKENS", "4096"))
WORKER_LOCK = threading.Lock()

for folder in (PENDING, RUNNING, COMPLETE, FAILED):
    folder.mkdir(parents=True, exist_ok=True)

# Jobs left in running after a crash are safe to retry. The GPU call may be repeated,
# but the stable job ID prevents duplicate queue entries or duplicate imports.
for job_file in RUNNING.glob("*.json"):
    job_file.replace(PENDING / job_file.name)


def authorized(handler: BaseHTTPRequestHandler) -> bool:
    if not TOKEN:
        return True
    return handler.headers.get("Authorization") == f"Bearer {TOKEN}"


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


def analyze(job: dict) -> list[dict]:
    local_zone = ZoneInfo(job.get("timezone") or TIMEZONE)
    screenshots = sorted(job["screenshots"], key=lambda shot: shot["captured_at"])
    content: list[dict] = [{
        "type": "text",
        "text": (
            "Create Dayflow timeline activity cards from these ordered screen captures. "
            "Return only a JSON object with a `cards` array. Each card must have "
            "start_time and end_time as local clock strings formatted h:mm AM/PM, "
            "category, subcategory, title, summary, and detailed_summary. "
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
    payload = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": content}],
        "temperature": 0.2,
        "max_tokens": MAX_TOKENS,
        "chat_template_kwargs": {"enable_thinking": False},
        "response_format": {"type": "json_object"},
    }).encode()
    request = urllib.request.Request(
        f"{GPU_URL}/chat/completions", data=payload,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    with urllib.request.urlopen(request, timeout=1800) as response:
        answer = json.load(response)["choices"][0]["message"]["content"]
    parsed = json.loads(answer)
    cards = parsed.get("cards") if isinstance(parsed, dict) else None
    if not isinstance(cards, list):
        raise ValueError("Model response did not contain a cards array")
    required = ("start_time", "end_time", "category", "subcategory", "title", "summary", "detailed_summary")
    if any(not isinstance(card, dict) or any(not isinstance(card.get(k), str) for k in required) for card in cards):
        raise ValueError("Model returned a card with missing or invalid fields")
    allowed_categories = {category.get("name") for category in job.get("categories", [])}
    for card in cards:
        for key in ("start_time", "end_time"):
            if not re.fullmatch(r"\d{1,2}:\d{2} [AP]M", card[key]):
                raise ValueError("Model returned a timestamp outside h:mm AM/PM format")
            datetime.strptime(card[key], "%I:%M %p")
        if allowed_categories and card["category"] not in allowed_categories:
            raise ValueError("Model returned a category not present in Dayflow settings")
    return cards


def worker() -> None:
    while True:
        time.sleep(20)
        if not WORKER_LOCK.acquire(blocking=False):
            continue
        try:
            jobs = sorted(PENDING.glob("*.json"), key=lambda path: path.stat().st_mtime)
            if not jobs:
                continue
            source = jobs[0]
            try:
                schedule = json.loads(source.read_text())
                if not in_window(schedule.get("schedule_timezone", TIMEZONE),
                                 schedule.get("window_start", WINDOW_START),
                                 schedule.get("window_end", WINDOW_END)):
                    continue
            except (ValueError, KeyError):
                print(f"Invalid schedule in {source.name}; using configured defaults", flush=True)
                if not in_window():
                    continue
            active = RUNNING / source.name
            try:
                source.replace(active)
                job = json.loads(active.read_text())
                result = {
                    "job_id": job["job_id"], "device_id": job["device_id"],
                    "batch_id": job["batch_id"], "cards": analyze(job),
                    "completed_at": datetime.now().astimezone().isoformat(),
                }
                temp = COMPLETE / (source.stem + ".tmp")
                temp.write_text(json.dumps(result, separators=(",", ":")))
                temp.replace(COMPLETE / source.name)
                active.unlink(missing_ok=True)
                print(f"Completed {job['job_id']}", flush=True)
            except Exception as error:
                try:
                    job = json.loads(active.read_text())
                    job["error"] = str(error)
                    job["attempts"] = int(job.get("attempts", 0)) + 1
                    if job["attempts"] < 5:
                        retry = PENDING / active.name
                        retry.write_text(json.dumps(job, separators=(",", ":")))
                    else:
                        (FAILED / active.name).write_text(json.dumps(job, separators=(",", ":")))
                    active.unlink(missing_ok=True)
                except Exception:
                    print(f"Could not recover job {active.name}: {error}", flush=True)
                print(f"Processing failed: {error}", flush=True)
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
            return self.respond(200, {"ok": True, "in_window": in_window(), "pending": len(list(PENDING.glob("*.json")))})
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
    print(f"Dayflow queue listening on {HOST}:{PORT}; GPU endpoint {GPU_URL}; hours {WINDOW_START}-{WINDOW_END} {TIMEZONE}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
