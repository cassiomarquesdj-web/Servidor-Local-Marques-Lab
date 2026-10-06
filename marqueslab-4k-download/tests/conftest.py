"""Shared test fixtures for Marques Lab 4K Download."""
from __future__ import annotations

import os
import subprocess
import sys
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from engine import ffmpeg_executable  # noqa: E402


@pytest.fixture(scope="session")
def ffmpeg_bin() -> str:
    binary = ffmpeg_executable()
    if not binary:
        pytest.skip("FFmpeg indisponível neste ambiente")
    return binary


@pytest.fixture(scope="session")
def sample_media(tmp_path_factory, ffmpeg_bin) -> Path:
    """A real 2-second H.264 + AAC MP4 produced by FFmpeg."""
    directory = tmp_path_factory.mktemp("media")
    video = directory / "Marques Lab Fixture.mp4"
    subprocess.run(
        [
            ffmpeg_bin, "-y", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=640x360:rate=25",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
            "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-movflags", "+faststart", str(video),
        ],
        check=True,
    )
    assert video.stat().st_size > 0
    return video


@pytest.fixture(scope="session")
def media_server(sample_media):
    """Serves the fixture over HTTP so downloads are exercised for real."""
    directory = sample_media.parent
    handler = partial(QuietHandler, directory=str(directory))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address[0], server.server_address[1]
    try:
        yield f"http://{host}:{port}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *args):  # noqa: D102 - silence the test output
        pass
