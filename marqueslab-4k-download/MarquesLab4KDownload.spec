# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller specification for Marques Lab 4K Download (macOS .app).

The FFmpeg binary is bundled so the distributed application never depends on a
user-installed FFmpeg. Set MARQUESLAB_TARGET_ARCH=universal2 to produce a
Universal 2 bundle (requires a universal2 Python and universal2 wheels).
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.abspath(SPECPATH))

from branding import (  # noqa: E402
    APP_NAME, BUNDLE_ID, COPYRIGHT, MINIMUM_MACOS, ORGANIZATION, VERSION,
)

ROOT = Path(SPECPATH)
TARGET_ARCH = os.environ.get("MARQUESLAB_TARGET_ARCH") or None
WINDOWS = sys.platform == "win32"
MACOS = sys.platform == "darwin"
ICON = ROOT / "assets" / ("AppIcon.ico" if WINDOWS else "AppIcon.icns")
EXE_SUFFIX = ".exe" if WINDOWS else ""


def resolve_ffmpeg() -> str:
    override = os.environ.get("MARQUESLAB_FFMPEG")
    if override:
        path = Path(override)
        if not path.is_file():
            raise SystemExit(f"MARQUESLAB_FFMPEG does not point to a file: {override}")
        return str(path)
    import imageio_ffmpeg

    return imageio_ffmpeg.get_ffmpeg_exe()


def stage(source: str, name: str) -> str:
    """Copy a binary under a stable name so it lands in the bundle as `name`.

    imageio-ffmpeg ships architecture-tagged filenames such as
    `ffmpeg-macos-aarch64-v7.1`; the application resolves `ffmpeg`.
    """
    import shutil

    staging = ROOT / "build" / "bundled"
    staging.mkdir(parents=True, exist_ok=True)
    target = staging / name
    shutil.copy2(source, target)
    target.chmod(0o755)
    return str(target)


FFMPEG = stage(resolve_ffmpeg(), "ffmpeg" + EXE_SUFFIX)
print(f"[spec] bundling FFmpeg as {FFMPEG}")

binaries = [(FFMPEG, ".")]
ffprobe = os.environ.get("MARQUESLAB_FFPROBE")
if ffprobe and Path(ffprobe).is_file():
    binaries.append((stage(ffprobe, "ffprobe" + EXE_SUFFIX), "."))
    print(f"[spec] bundling ffprobe from {ffprobe}")

datas = []
if ICON.exists():
    datas.append((str(ICON), "assets"))

def windows_version_file() -> str | None:
    """Metadata Explorer shows on the .exe properties panel."""
    if not WINDOWS:
        return None
    numbers = tuple(int(part) for part in VERSION.split(".")) + (0,)
    target = ROOT / "build" / "version_info.txt"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(f"""VSVersionInfo(
  ffi=FixedFileInfo(
    filevers={numbers[:4]}, prodvers={numbers[:4]},
    mask=0x3f, flags=0x0, OS=0x40004, fileType=0x1, subtype=0x0, date=(0, 0)
  ),
  kids=[
    StringFileInfo([StringTable('040904B0', [
      StringStruct('CompanyName', '{ORGANIZATION}'),
      StringStruct('FileDescription', '{APP_NAME}'),
      StringStruct('FileVersion', '{VERSION}'),
      StringStruct('InternalName', '{APP_NAME}'),
      StringStruct('LegalCopyright', '{COPYRIGHT}'),
      StringStruct('OriginalFilename', '{APP_NAME}.exe'),
      StringStruct('ProductName', '{APP_NAME}'),
      StringStruct('ProductVersion', '{VERSION}')])]),
    VarFileInfo([VarStruct('Translation', [1033, 1200])])
  ]
)
""", encoding="utf-8")
    return str(target)


a = Analysis(
    ["app.py"],
    pathex=[str(ROOT)],
    binaries=binaries,
    datas=datas,
    hiddenimports=["yt_dlp"],
    hookspath=[],
    runtime_hooks=[],
    excludes=[
        "tkinter", "test", "unittest", "pydoc_data", "pytest",
        "PySide6.QtQml", "PySide6.QtQuick", "PySide6.QtQuick3D",
        "PySide6.QtWebEngineCore", "PySide6.QtWebEngineWidgets",
        "PySide6.QtMultimedia", "PySide6.Qt3DCore", "PySide6.QtCharts",
        "PySide6.QtDataVisualization", "PySide6.QtDesigner",
    ],
    noarchive=False,
)

def drop_duplicate_ffmpeg(entries):
    """imageio-ffmpeg carries its own 50 MB FFmpeg; the bundle already has one."""
    kept = []
    for entry in entries:
        dest = entry[0].replace("\\", "/")
        if "imageio_ffmpeg/binaries/" in dest:
            print(f"[spec] dropping duplicated payload: {dest}")
            continue
        kept.append(entry)
    return kept


a.binaries = drop_duplicate_ffmpeg(a.binaries)
a.datas = drop_duplicate_ffmpeg(a.datas)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name=APP_NAME,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=TARGET_ARCH,
    codesign_identity=None,
    entitlements_file=None,
    icon=str(ICON) if ICON.exists() else None,
    version=windows_version_file(),
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name=APP_NAME,
)

app = None if not MACOS else BUNDLE(
    coll,
    name=f"{APP_NAME}.app",
    icon=str(ICON) if ICON.exists() else None,
    bundle_identifier=BUNDLE_ID,
    version=VERSION,
    info_plist={
        "CFBundleName": APP_NAME,
        "CFBundleDisplayName": APP_NAME,
        "CFBundleShortVersionString": VERSION,
        "CFBundleVersion": VERSION,
        "LSMinimumSystemVersion": MINIMUM_MACOS,
        "LSApplicationCategoryType": "public.app-category.utilities",
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": COPYRIGHT,
        "NSRequiresAquaSystemAppearance": False,
    },
)
