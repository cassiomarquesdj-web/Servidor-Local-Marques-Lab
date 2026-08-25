"""Instagram support: session handling, silent-media detection and messaging.

Public Instagram posts download anonymously with audio, exactly like YouTube —
measured: H.264 video with AAC audio, no conversion needed for After Effects.
A browser session is only required for what the site itself withholds from
anonymous visitors: private accounts, restricted posts and stories.

A file with no audio track is not proof of a login wall — the media may simply
be silent — so the warning must state both possibilities.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from engine import DownloadEngine, choose_audio, choose_video, friendly_error


def render_silent(ffmpeg: str, target: Path) -> Path:
    subprocess.run(
        [
            ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=320x240:rate=15", "-t", "2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-an", str(target),
        ],
        check=True,
    )
    return target


def test_browser_session_is_off_by_default(tmp_path):
    engine = DownloadEngine(tmp_path)
    assert engine.browser_session is None
    assert "cookiesfrombrowser" not in engine.build_options(choose_video())


def test_browser_session_is_passed_to_ytdlp(tmp_path):
    engine = DownloadEngine(tmp_path, browser_session="firefox")
    assert engine.build_options(choose_video())["cookiesfrombrowser"] == ("firefox",)
    assert engine.build_options(choose_audio())["cookiesfrombrowser"] == ("firefox",)


def test_empty_session_string_disables_cookies(tmp_path):
    assert DownloadEngine(tmp_path, browser_session="").browser_session is None


def test_silent_download_is_flagged(tmp_path, ffmpeg_bin):
    """A mute clip is a failure for an editor and must never pass silently."""
    engine = DownloadEngine(tmp_path)
    silent = render_silent(ffmpeg_bin, tmp_path / "reel.mp4")
    warnings = engine._audio_warnings([silent])
    assert warnings
    assert "não tem faixa de áudio" in warnings[0]
    assert "muda na origem" in warnings[0], "não afirme login sem saber: a mídia pode ser muda"
    assert "sessão do navegador" in warnings[0]
    assert "reel.mp4" in warnings[0]


def test_media_with_audio_produces_no_warning(tmp_path, sample_media):
    engine = DownloadEngine(tmp_path)
    assert engine._audio_warnings([sample_media]) == []


def test_audio_inspection_never_breaks_a_download(tmp_path):
    engine = DownloadEngine(tmp_path)
    assert engine._audio_warnings([tmp_path / "nao-existe.mp4"]) == []


@pytest.mark.parametrize("raw,expected", [
    (
        "ERROR: [Instagram] X: Instagram sent an empty media response. Check if this post...",
        "sessão do navegador",
    ),
    ("ERROR: Requested content is not available, rate-limit reached", "limite de requisições"),
    ("ERROR: login required to access this content", "sessão autenticada"),
])
def test_instagram_failures_are_explained(raw, expected):
    assert expected in friendly_error(raw)


def test_instagram_urls_are_accepted_by_the_engine():
    from engine import normalize_url, split_urls

    urls = split_urls(
        "https://www.instagram.com/reel/Chunk8-jurw/\n"
        "https://instagram.com/p/aye83DjauH/\n"
        "https://www.instagram.com/tv/BkfuX9UB-eK/"
    )
    assert len(urls) == 3
    assert normalize_url("  https://www.instagram.com/reel/abc/  ") == "https://www.instagram.com/reel/abc/"
