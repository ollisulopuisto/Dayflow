"""Window rules for the Studio queue: the server's environment decides, never the upload."""

import importlib
import os
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

HELSINKI = ZoneInfo("Europe/Helsinki")


def load_server(window_start: str, window_end: str):
    os.environ["DAYFLOW_QUEUE_DIR"] = tempfile.mkdtemp(prefix="dayflow-queue-test-")
    os.environ["DAYFLOW_WINDOW_START"] = window_start
    os.environ["DAYFLOW_WINDOW_END"] = window_end
    os.environ["DAYFLOW_TIMEZONE"] = "Europe/Helsinki"
    sys.path.insert(0, str(Path(__file__).parent))
    sys.modules.pop("server", None)
    return importlib.import_module("server")


class ServerWindowTests(unittest.TestCase):
    def setUp(self) -> None:
        # Server window is night: 01:00-07:00 Helsinki.
        self.server = load_server("01:00", "07:00")

    def test_upload_window_is_ignored_during_the_day(self) -> None:
        # The laptop asks for 07:00-01:00 (day). At 10:00 the server's night window is closed,
        # so the job must not run.
        upload = {"window_start": "07:00", "window_end": "01:00", "schedule_timezone": "Europe/Helsinki"}
        noon = datetime(2026, 10, 15, 10, 0, tzinfo=HELSINKI)
        self.assertFalse(self.server.may_process(upload, now=noon))

    def test_upload_window_cannot_open_the_night_for_a_day_server(self) -> None:
        # The laptop asks for 01:00-07:00 (night) but the server window is day-only.
        server = load_server("07:00", "01:00")
        upload = {"window_start": "01:00", "window_end": "07:00", "schedule_timezone": "Europe/Helsinki"}
        three = datetime(2026, 10, 15, 3, 0, tzinfo=HELSINKI)
        self.assertFalse(server.may_process(upload, now=three))

    def test_server_window_decides_when_upload_has_no_schedule(self) -> None:
        three = datetime(2026, 10, 15, 3, 0, tzinfo=HELSINKI)
        self.assertTrue(self.server.may_process({}, now=three))
        noon = datetime(2026, 10, 15, 12, 0, tzinfo=HELSINKI)
        self.assertFalse(self.server.may_process({}, now=noon))

    def test_stored_upload_schedule_is_not_used_by_the_worker(self) -> None:
        # The job's own schedule must not change the answer, even when it is garbage.
        garbage = {"window_start": "99:99", "window_end": "nope", "schedule_timezone": "Mars/Olympus"}
        three = datetime(2026, 10, 15, 3, 0, tzinfo=HELSINKI)
        self.assertTrue(self.server.may_process(garbage, now=three))


if __name__ == "__main__":
    unittest.main()
