"""Downloads run in a child process so they can actually be stopped.

A Python thread blocked in a socket read cannot be interrupted: a cancelled job
kept downloading in the background, stealing bandwidth from the next one, while
the interface waited forever for a worker that could not answer.
"""
from __future__ import annotations

import io
import json
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path
from urllib.parse import quote

from engine import DownloadEngine, choose_audio, choose_video, run_worker, worker_command


def spec_for(url: str, out: Path, choice=None) -> dict:
    return {
        "url": url,
        "output": str(out),
        "playlist": False,
        "browser_session": None,
        "choice": asdict(choice or choose_video("1080p")),
    }


def events_from(stream: io.StringIO) -> list[dict]:
    return [json.loads(line) for line in stream.getvalue().splitlines() if line.strip()]


def test_worker_downloads_and_reports_done(tmp_path, media_server, sample_media):
    out = io.StringIO()
    url = f"{media_server}/{quote(sample_media.name)}"
    assert run_worker(spec_for(url, tmp_path / "out"), out) == 0

    events = events_from(out)
    done = [e for e in events if e["event"] == "done"]
    assert done, events[-3:]
    assert done[0]["files"]
    assert Path(done[0]["files"][0]).exists()
    assert any(e["event"] == "progress" for e in events)


def test_worker_reports_failure_as_json(tmp_path, media_server):
    out = io.StringIO()
    assert run_worker(spec_for(f"{media_server}/nao-existe.mp4", tmp_path / "out"), out) == 1
    failed = [e for e in events_from(out) if e["event"] == "failed"]
    assert failed and failed[0]["message"]


def test_worker_handles_audio_jobs(tmp_path, media_server, sample_media):
    out = io.StringIO()
    url = f"{media_server}/{quote(sample_media.name)}"
    assert run_worker(spec_for(url, tmp_path / "audio", choose_audio()), out) == 0
    done = [e for e in events_from(out) if e["event"] == "done"][0]
    assert any(f.endswith(".mp3") for f in done["files"])


def test_worker_command_targets_the_app_binary_when_frozen(monkeypatch):
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "executable", "/Apps/Demo.app/Contents/MacOS/Demo")
    command = worker_command({"url": "https://example.com/a"})
    assert command[0] == "/Apps/Demo.app/Contents/MacOS/Demo"
    assert command[1] == "--download-worker"
    assert json.loads(command[2])["url"] == "https://example.com/a"


def test_worker_command_runs_from_source(monkeypatch):
    monkeypatch.setattr(sys, "frozen", False, raising=False)
    command = worker_command({"url": "https://example.com/a"})
    assert command[1].endswith("app.py")
    assert command[2] == "--download-worker"


def test_worker_command_is_runnable(tmp_path, media_server, sample_media):
    """The CLI entry point stays available for headless and scripted runs."""
    url = f"{media_server}/{quote(sample_media.name)}"
    command = worker_command(spec_for(url, tmp_path / "cli"))
    process = subprocess.run(command, capture_output=True, text=True, timeout=180)
    assert process.returncode == 0, process.stderr[-500:]
    assert any(json.loads(l)["event"] == "done" for l in process.stdout.splitlines() if l.strip())
