"""FFmpeg discovery, including the layouts produced by a frozen macOS bundle."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

import engine
from engine import FFmpegNotFound, ffmpeg_executable, ffprobe_executable, require_ffmpeg


def _fake_binary(path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/sh\nexit 0\n")
    path.chmod(0o755)
    return path


def test_ffmpeg_is_discoverable():
    assert ffmpeg_executable(), "FFmpeg deve existir no ambiente de desenvolvimento ou CI"


def test_resolved_ffmpeg_actually_runs():
    binary = ffmpeg_executable()
    result = subprocess.run([binary, "-version"], capture_output=True, text=True)
    assert result.returncode == 0
    assert "ffmpeg version" in result.stdout


def test_require_ffmpeg_raises_when_absent(monkeypatch):
    monkeypatch.setattr(engine, "ffmpeg_executable", lambda: None)
    with pytest.raises(FFmpegNotFound):
        require_ffmpeg()


def test_bundled_ffmpeg_wins_over_path(monkeypatch, tmp_path):
    """PyInstaller's --add-binary src:ffmpeg creates a *directory* named ffmpeg."""
    bundled = _fake_binary(tmp_path / "ffmpeg" / "ffmpeg")
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "_MEIPASS", str(tmp_path), raising=False)
    assert ffmpeg_executable() == str(bundled)


def test_bundled_ffmpeg_at_bundle_root(monkeypatch, tmp_path):
    bundled = _fake_binary(tmp_path / "ffmpeg")
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "_MEIPASS", str(tmp_path), raising=False)
    assert ffmpeg_executable() == str(bundled)


def test_directory_named_ffmpeg_is_never_returned(monkeypatch, tmp_path):
    """Regression: a directory used to be returned as if it were the binary."""
    (tmp_path / "ffmpeg").mkdir()
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "_MEIPASS", str(tmp_path), raising=False)
    resolved = ffmpeg_executable()
    assert resolved is None or Path(resolved).is_file()


def test_non_executable_file_is_ignored(monkeypatch, tmp_path):
    stub = tmp_path / "ffmpeg"
    stub.write_text("not executable")
    stub.chmod(0o644)
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setattr(sys, "_MEIPASS", str(tmp_path), raising=False)
    resolved = ffmpeg_executable()
    assert resolved != str(stub)


def test_app_bundle_frameworks_layout(monkeypatch, tmp_path):
    """dist/App.app/Contents/Frameworks/ffmpeg must be discoverable."""
    contents = tmp_path / "App.app" / "Contents"
    executable = _fake_binary(contents / "MacOS" / "App")
    bundled = _fake_binary(contents / "Frameworks" / "ffmpeg")
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.delattr(sys, "_MEIPASS", raising=False)
    monkeypatch.setattr(sys, "executable", str(executable))
    assert ffmpeg_executable() == str(bundled)


def test_source_run_does_not_read_bundle_paths(monkeypatch, tmp_path):
    _fake_binary(tmp_path / "ffmpeg")
    monkeypatch.setattr(sys, "frozen", False, raising=False)
    monkeypatch.setattr(sys, "_MEIPASS", str(tmp_path), raising=False)
    assert ffmpeg_executable() != str(tmp_path / "ffmpeg")


def test_ffprobe_lookup_is_optional():
    resolved = ffprobe_executable()
    assert resolved is None or Path(resolved).is_file()
