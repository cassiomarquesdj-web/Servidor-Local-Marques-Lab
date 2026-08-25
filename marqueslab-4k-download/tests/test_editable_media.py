"""Guarantee that the video profile produces files Premiere/After Effects open.

YouTube's preferred streams are AV1 or VP9 with Opus audio. Both play in a
browser and both are rejected by Premiere Pro and After Effects, which was the
defect these tests lock down.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from engine import (
    EDITABLE_AUDIO_CODECS, EDITABLE_VIDEO_CODECS, DownloadEngine, choose_video,
    ensure_editable, probe_media,
)


def render(ffmpeg: str, target: Path, *, vcodec: str, acodec: str, seconds: int = 2) -> Path:
    command = [
        ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", f"testsrc=size=320x240:rate=15",
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
        "-t", str(seconds), "-pix_fmt", "yuv420p",
    ]
    if vcodec == "libvpx-vp9":
        command += ["-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "8", "-b:v", "300k"]
    else:
        command += ["-c:v", vcodec]
    command += ["-c:a", acodec, str(target)]
    subprocess.run(command, check=True, capture_output=True)
    assert target.stat().st_size > 0
    return target


@pytest.fixture
def incompatible(tmp_path, ffmpeg_bin) -> Path:
    """VP9 + Opus — exactly what the editors refuse."""
    return render(ffmpeg_bin, tmp_path / "vp9_opus.webm", vcodec="libvpx-vp9", acodec="libopus")


@pytest.fixture
def wrong_audio_only(tmp_path, ffmpeg_bin) -> Path:
    return render(ffmpeg_bin, tmp_path / "h264_opus.mkv", vcodec="libx264", acodec="libopus")


@pytest.fixture
def already_editable(tmp_path, ffmpeg_bin) -> Path:
    return render(ffmpeg_bin, tmp_path / "h264_aac.mp4", vcodec="libx264", acodec="aac")


def test_probe_media_reads_codecs_and_duration(already_editable):
    video, audio, duration = probe_media(already_editable)
    assert video == "h264"
    assert audio == "aac"
    assert duration and duration > 1.5


def test_incompatible_media_is_converted(incompatible):
    result = ensure_editable(incompatible)
    video, audio, _ = probe_media(result)
    assert video in EDITABLE_VIDEO_CODECS
    assert audio in EDITABLE_AUDIO_CODECS


def test_conversion_reports_progress(incompatible):
    events: list[dict] = []
    ensure_editable(incompatible, events.append)
    statuses = {event["status"] for event in events}
    assert "converting" in statuses
    assert "converted" in statuses
    assert events[-1]["percent"] == 100


def test_only_the_audio_is_re_encoded_when_the_video_is_fine(wrong_audio_only):
    events: list[dict] = []
    result = ensure_editable(wrong_audio_only, events.append)
    video, audio, _ = probe_media(result)
    assert video == "h264"
    assert audio == "aac"
    converting = [e for e in events if e["status"] == "converting"]
    assert converting and converting[0]["conversion"] == "audio"


def test_compatible_media_is_left_untouched(already_editable):
    before = already_editable.stat()
    events: list[dict] = []
    result = ensure_editable(already_editable, events.append)
    after = result.stat()
    assert result == already_editable
    assert (after.st_size, after.st_mtime) == (before.st_size, before.st_mtime)
    assert events == [], "não deve reprocessar mídia que já é editável"


def test_conversion_writes_an_mp4_and_removes_the_source(incompatible):
    """WebM cannot hold H.264/AAC, so the converted file must become an MP4."""
    original = incompatible
    result = ensure_editable(incompatible)
    assert result.suffix == ".mp4"
    assert result.exists()
    assert not original.exists(), "o arquivo original incompatível deve ser removido"
    assert not list(result.parent.glob("*.editavel.*")), "sobrou arquivo temporário"


def test_mp4_source_is_converted_in_place(tmp_path, ffmpeg_bin):
    source = render(ffmpeg_bin, tmp_path / "av_wrong.mp4", vcodec="libx264", acodec="libopus")
    result = ensure_editable(source)
    assert result == source
    assert probe_media(result)[1] in EDITABLE_AUDIO_CODECS


def test_downloaded_video_is_editable_end_to_end(tmp_path, media_server, ffmpeg_bin):
    """A source serving VP9/Opus must still land as H.264/AAC on disk."""
    source_dir = tmp_path / "served"
    source_dir.mkdir()
    render(ffmpeg_bin, source_dir / "Marques Lab VP9.webm", vcodec="libvpx-vp9", acodec="libopus")

    import threading
    from functools import partial
    from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
    from urllib.parse import quote

    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Quiet, directory=str(source_dir)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        url = f"http://127.0.0.1:{server.server_address[1]}/{quote('Marques Lab VP9.webm')}"
        engine = DownloadEngine(tmp_path / "out")
        result = engine.download(url, choose_video("1080p"))
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert result.files
    video, audio, _ = probe_media(result.primary)
    assert video in EDITABLE_VIDEO_CODECS, f"vídeo saiu como {video}"
    assert audio in EDITABLE_AUDIO_CODECS, f"áudio saiu como {audio}"


def test_raw_profile_does_not_convert(tmp_path, media_server, sample_media):
    """The maximum-quality profile must never re-encode behind the user's back."""
    from urllib.parse import quote

    engine = DownloadEngine(tmp_path / "raw")
    events: list[dict] = []
    engine.progress = events.append
    engine.download(f"{media_server}/{quote(sample_media.name)}", choose_video("1080p", editable=False))
    assert not [e for e in events if e.get("status") in {"converting", "converted"}]
