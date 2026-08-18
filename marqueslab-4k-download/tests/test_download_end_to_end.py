"""Real downloads through the engine against a local HTTP server.

These tests exercise the whole path — yt-dlp fetching over HTTP, FFmpeg
post-processing, file naming and the produced-file bookkeeping — without
depending on any third-party website.
"""
from __future__ import annotations

import re
import subprocess
import threading
from pathlib import Path
from urllib.parse import quote

import pytest

from engine import DownloadCancelled, DownloadEngine, choose_audio, choose_video


def probe(ffmpeg_bin: str, path: Path) -> str:
    """Return FFmpeg's stream banner for `path`.

    ffprobe is deliberately not required: the distributed application bundles
    FFmpeg only, so the tests must validate media with the same tool the app has.
    """
    result = subprocess.run(
        [ffmpeg_bin, "-hide_banner", "-i", str(path), "-f", "null", "-"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, f"FFmpeg não conseguiu decodificar {path}:\n{result.stderr}"
    return result.stderr


def duration_seconds(banner: str) -> float:
    match = re.search(r"Duration: (\d+):(\d+):(\d+\.\d+)", banner)
    assert match, f"duração não encontrada em:\n{banner}"
    hours, minutes, seconds = match.groups()
    return int(hours) * 3600 + int(minutes) * 60 + float(seconds)


@pytest.fixture
def media_url(media_server, sample_media) -> str:
    return f"{media_server}/{quote(sample_media.name)}"


def test_downloads_real_video(tmp_path, media_url, ffmpeg_bin):
    engine = DownloadEngine(tmp_path / "out")
    result = engine.download(media_url, choose_video("1080p"))

    assert result.files, "nenhum arquivo foi registrado pelo engine"
    produced = result.primary
    assert produced.exists() and produced.stat().st_size > 0
    assert produced.parent == (tmp_path / "out")

    banner = probe(ffmpeg_bin, produced)
    assert duration_seconds(banner) > 1.0
    assert "Video:" in banner
    assert "Audio:" in banner


def test_extracts_real_mp3(tmp_path, media_url, ffmpeg_bin):
    engine = DownloadEngine(tmp_path / "audio")
    result = engine.download(media_url, choose_audio())

    mp3s = [f for f in result.files if f.suffix == ".mp3"]
    assert mp3s, f"nenhum MP3 produzido (arquivos: {result.files})"
    produced = mp3s[0]
    assert produced.stat().st_size > 0

    banner = probe(ffmpeg_bin, produced)
    assert "Audio: mp3" in banner, banner
    assert "Video:" not in banner, "o MP3 não deve conter faixa de vídeo"
    assert duration_seconds(banner) > 1.0


def test_progress_callback_receives_bytes(tmp_path, media_url):
    events: list[dict] = []
    engine = DownloadEngine(tmp_path / "progress", events.append)
    engine.download(media_url, choose_video())

    assert events, "nenhum evento de progresso emitido"
    assert any(event.get("status") == "finished" for event in events)
    assert any((event.get("downloaded_bytes") or 0) > 0 for event in events)


def test_output_filename_keeps_media_title(tmp_path, media_url):
    engine = DownloadEngine(tmp_path / "named")
    result = engine.download(media_url, choose_video())
    assert "Marques Lab Fixture" in result.primary.name


def test_cancellation_stops_the_download(tmp_path, media_url):
    engine = DownloadEngine(tmp_path / "cancel")
    ready = threading.Event()

    def on_progress(_event: dict) -> None:
        ready.set()
        engine.cancel()

    engine.progress = on_progress
    with pytest.raises(DownloadCancelled):
        engine.download(media_url, choose_video())
    assert ready.is_set()


def test_invalid_url_is_rejected_before_network(tmp_path):
    engine = DownloadEngine(tmp_path / "invalid")
    with pytest.raises(ValueError):
        engine.download("ftp://example.com/file.mp4", choose_video())


def test_missing_media_raises(tmp_path, media_server):
    engine = DownloadEngine(tmp_path / "missing")
    with pytest.raises(Exception) as excinfo:
        engine.download(f"{media_server}/nao-existe.mp4", choose_video())
    assert not isinstance(excinfo.value, DownloadCancelled)


def test_analyze_reports_metadata(tmp_path, media_url):
    engine = DownloadEngine(tmp_path / "analyze")
    summary = engine.summarize(engine.analyze(media_url))
    assert summary["title"]
    assert summary["is_playlist"] is False
