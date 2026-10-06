"""Windows packaging and platform behaviour.

The application ships on macOS and Windows from one codebase, so every
platform-specific decision is pinned here instead of being discovered by a user
on the other operating system.
"""
from __future__ import annotations

import os
import struct
import sys
from pathlib import Path

import pytest

import engine

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT.parent / ".github" / "workflows" / "marqueslab-4k-download-windows.yml"
INSTALLER = ROOT / "packaging" / "windows" / "marqueslab.iss"


# --------------------------------------------------------------------- icon
def test_windows_icon_is_committed():
    icon = ROOT / "assets" / "AppIcon.ico"
    assert icon.is_file(), "o .ico precisa estar versionado para o build do Windows"
    reserved, kind, count = struct.unpack_from("<HHH", icon.read_bytes(), 0)
    assert (reserved, kind) == (0, 1), "cabeçalho de ícone do Windows inválido"
    assert count >= 4


def test_windows_icon_covers_the_sizes_explorer_uses():
    sys.path.insert(0, str(ROOT / "tools"))
    from icopack import describe

    sizes = {w for w, _ in describe(ROOT / "assets" / "AppIcon.ico")}
    assert {16, 32, 256} <= sizes, f"faltam tamanhos no ícone: {sorted(sizes)}"
    assert len(sizes) == len(describe(ROOT / "assets" / "AppIcon.ico")), "tamanhos duplicados"


# ------------------------------------------------------------------ runtime
def test_support_dir_uses_appdata_on_windows(monkeypatch, tmp_path):
    pytest.importorskip("PySide6")
    import app as app_module

    monkeypatch.setattr(sys, "platform", "win32")
    monkeypatch.setenv("APPDATA", str(tmp_path / "Roaming"))
    target = app_module.support_dir()
    assert target.parent == tmp_path / "Roaming"
    assert target.is_dir()


def test_support_dir_never_lands_in_the_download_folder(monkeypatch, tmp_path):
    pytest.importorskip("PySide6")
    import app as app_module

    monkeypatch.setattr(sys, "platform", "win32")
    monkeypatch.setenv("APPDATA", str(tmp_path))
    assert "Downloads" not in str(app_module.support_dir())


def test_executable_detection_without_a_permission_bit(monkeypatch, tmp_path):
    """Windows has no execute bit: the extension decides."""
    exe = tmp_path / "ffmpeg.exe"
    exe.write_bytes(b"MZ")
    exe.chmod(0o644)
    monkeypatch.setattr(engine, "is_windows", lambda: True)
    assert engine._is_executable_file(exe)
    txt = tmp_path / "leiame.txt"
    txt.write_text("x")
    assert not engine._is_executable_file(txt)


def test_bundle_lookup_covers_the_windows_layout(monkeypatch, tmp_path):
    """PyInstaller 6 keeps the payload of a one-folder build in _internal."""
    internal = tmp_path / "_internal"
    internal.mkdir()
    bundled = internal / "ffmpeg.exe"
    bundled.write_bytes(b"MZ")
    bundled.chmod(0o755)

    monkeypatch.setattr(engine, "is_windows", lambda: True)
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.delattr(sys, "_MEIPASS", raising=False)
    monkeypatch.setattr(sys, "executable", str(tmp_path / "Marques Lab 4K Download.exe"))

    assert engine.ffmpeg_executable() == str(bundled)


def test_windows_prefers_a_hardware_encoder(monkeypatch):
    monkeypatch.setattr(sys, "platform", "win32")
    monkeypatch.setattr(engine, "available_encoders", lambda _f: " h264_nvenc  h264_qsv ")
    monkeypatch.setattr(engine, "encoder_works", lambda *_a: True)
    assert engine._h264_encoder("ffmpeg")[:2] == ["-c:v", "h264_nvenc"]


def test_software_encoder_is_the_fallback(monkeypatch):
    monkeypatch.setattr(sys, "platform", "win32")
    monkeypatch.setattr(engine, "available_encoders", lambda _f: "libx264")
    assert engine._h264_encoder("ffmpeg")[:2] == ["-c:v", "libx264"]


def test_filenames_are_sanitised_for_windows(monkeypatch, tmp_path):
    monkeypatch.setattr(engine, "is_windows", lambda: True)
    opts = engine.DownloadEngine(tmp_path).build_options(engine.choose_video())
    assert opts["windowsfilenames"] is True


# ---------------------------------------------------------------- packaging
def test_spec_builds_for_windows_too():
    spec = (ROOT / "MarquesLab4KDownload.spec").read_text(encoding="utf-8")
    assert 'AppIcon.ico' in spec
    assert 'EXE_SUFFIX' in spec, "o FFmpeg embarcado precisa virar ffmpeg.exe"
    assert 'if not MACOS else BUNDLE' in spec, "BUNDLE é exclusivo do macOS"
    assert 'windows_version_file' in spec


def test_windows_workflow_proves_the_package_works():
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "runs-on: windows-latest" in text
    assert "pytest" in text
    assert "--self-test-download" in text, "o CI precisa provar um download real no .exe"
    assert "upload-artifact" in text


def test_windows_workflow_ships_installer_and_portable():
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "ISCC.exe" in text, "instalador do Inno Setup"
    assert "Compress-Archive" in text, "pacote portátil"
    assert "release/*.exe" in text and "release/*.zip" in text


def test_installer_does_not_require_administrator():
    text = INSTALLER.read_text(encoding="utf-8")
    assert "PrivilegesRequired=lowest" in text
    assert "recursesubdirs" in text, "todo o conteúdo precisa ser instalado"
    assert "AppIcon.ico" in text
    assert "{app}\\{#AppName}.exe" in text


def test_installer_creates_shortcuts():
    text = INSTALLER.read_text(encoding="utf-8")
    assert "[Icons]" in text
    assert "autodesktop" in text
    assert "uninstallexe" in text, "precisa existir desinstalador"


def test_listed_encoder_is_not_assumed_to_work(monkeypatch):
    """A build can advertise h264_nvenc on a machine with no NVIDIA driver."""
    monkeypatch.setattr(sys, "platform", "win32")
    monkeypatch.setattr(engine, "available_encoders", lambda _f: "h264_nvenc h264_qsv libx264")
    monkeypatch.setattr(engine, "encoder_works", lambda *_a: False)
    assert engine._h264_encoder("ffmpeg") == engine.SOFTWARE_H264


def test_first_working_hardware_encoder_wins(monkeypatch):
    monkeypatch.setattr(sys, "platform", "win32")
    monkeypatch.setattr(engine, "available_encoders", lambda _f: "h264_nvenc h264_qsv")
    monkeypatch.setattr(engine, "encoder_works", lambda _f, name, _a: name == "h264_qsv")
    assert engine._h264_encoder("ffmpeg")[:2] == ["-c:v", "h264_qsv"]


def test_encoder_probe_detects_a_real_encoder(ffmpeg_bin):
    assert engine.encoder_works(ffmpeg_bin, "libx264", ["-preset", "ultrafast"])


def test_encoder_probe_rejects_a_missing_encoder(ffmpeg_bin):
    engine._ENCODER_CACHE.clear()
    assert not engine.encoder_works(ffmpeg_bin, "h264_naoexiste", [])
