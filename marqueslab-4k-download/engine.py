"""Download engine for Marques Lab 4K Download.

The engine is a thin, well-defined boundary around yt-dlp and FFmpeg. It owns
media resolution, format selection, cancellation and the discovery of the
FFmpeg binary that ships inside the frozen macOS application. Everything above
this layer (queue, history, UI state) lives in the application layer.
"""
from __future__ import annotations

import os
import re
import shutil
import sys
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable
from urllib.parse import urlparse

import yt_dlp

try:
    import imageio_ffmpeg
except ImportError:  # pragma: no cover - optional at runtime
    imageio_ffmpeg = None


VIDEO_SELECTORS: dict[str, str] = {
    "2160p": "bestvideo[height<=2160]+bestaudio/best[height<=2160]/best",
    "1440p": "bestvideo[height<=1440]+bestaudio/best[height<=1440]/best",
    "1080p": "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best",
    "720p": "bestvideo[height<=720]+bestaudio/best[height<=720]/best",
    "best": "bestvideo+bestaudio/best",
}


@dataclass(frozen=True)
class MediaChoice:
    mode: str
    quality: str
    format_selector: str
    extension: str


@dataclass
class DownloadResult:
    """Outcome of a single download job."""

    files: list[Path] = field(default_factory=list)
    titles: list[str] = field(default_factory=list)

    @property
    def primary(self) -> Path | None:
        return self.files[0] if self.files else None


class DownloadCancelled(Exception):
    """Raised internally when the user cancels an active download."""


class FFmpegNotFound(RuntimeError):
    """Raised when no usable FFmpeg binary can be resolved."""


def normalize_url(value: str) -> str:
    value = value.strip()
    if not value:
        raise ValueError("URL vazia")
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("Informe uma URL HTTP/HTTPS válida")
    return value


def split_urls(value: str) -> list[str]:
    urls: list[str] = []
    for raw in re.split(r"[\r\n\t]+", value):
        raw = raw.strip()
        if not raw:
            continue
        urls.append(normalize_url(raw))
    return list(dict.fromkeys(urls))


def safe_filename(name: str) -> str:
    name = re.sub(r"[\\/:*?\"<>|\x00-\x1f]", "_", name).strip(" .")
    return name[:180] or "MarquesLab_Media"


def choose_video(quality: str = "best") -> MediaChoice:
    quality = quality if quality in VIDEO_SELECTORS else "best"
    return MediaChoice("video", quality, VIDEO_SELECTORS[quality], "mp4")


def choose_audio(bitrate: str = "320") -> MediaChoice:
    return MediaChoice("audio", f"{bitrate} kbps", "bestaudio/best", "mp3")


def _is_executable_file(path: Path) -> bool:
    return path.is_file() and os.access(path, os.X_OK)


def _bundle_search_roots() -> list[Path]:
    """Directories that may hold binaries inside a frozen macOS/Windows build.

    PyInstaller's ``--add-binary src:ffmpeg`` places the binary in a *directory*
    named ``ffmpeg`` inside the bundle, while ``--add-binary src:.`` places it at
    the bundle root. In a macOS .app the runtime root is ``Contents/Frameworks``
    but resources may also be resolved from ``Contents/Resources``. All of those
    layouts are probed so the packaged app never falls back to a system FFmpeg
    the user does not have.
    """
    roots: list[Path] = []
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        root = Path(meipass)
        roots += [root, root / "ffmpeg", root / "bin"]
    exe_dir = Path(sys.executable).resolve().parent
    roots += [exe_dir, exe_dir / "ffmpeg"]
    # dist/App.app/Contents/MacOS/App -> Contents
    contents = exe_dir.parent
    if contents.name == "Contents":
        for sub in ("Frameworks", "Resources", "MacOS"):
            roots += [contents / sub, contents / sub / "ffmpeg"]
    seen: set[Path] = set()
    unique: list[Path] = []
    for candidate in roots:
        if candidate not in seen:
            seen.add(candidate)
            unique.append(candidate)
    return unique


def _find_bundled(names: Iterable[str]) -> str | None:
    if not getattr(sys, "frozen", False):
        return None
    for root in _bundle_search_roots():
        for name in names:
            candidate = root / name
            if _is_executable_file(candidate):
                return str(candidate)
    return None


def ffmpeg_executable() -> str | None:
    """Resolve FFmpeg: bundled binary first, then imageio-ffmpeg, then PATH."""
    bundled = _find_bundled(("ffmpeg", "ffmpeg.exe"))
    if bundled:
        return bundled
    if imageio_ffmpeg is not None:
        try:
            candidate = imageio_ffmpeg.get_ffmpeg_exe()
            if candidate and Path(candidate).is_file():
                return candidate
        except Exception:  # pragma: no cover - imageio internal failure
            pass
    return shutil.which("ffmpeg")


def ffprobe_executable() -> str | None:
    """Resolve ffprobe when available (optional: yt-dlp degrades gracefully)."""
    bundled = _find_bundled(("ffprobe", "ffprobe.exe"))
    if bundled:
        return bundled
    return shutil.which("ffprobe")


def require_ffmpeg() -> str:
    ffmpeg = ffmpeg_executable()
    if not ffmpeg:
        raise FFmpegNotFound(
            "FFmpeg não encontrado. A versão empacotada do Marques Lab 4K "
            "Download inclui FFmpeg; em execução a partir do código-fonte, "
            "instale o FFmpeg ou o pacote imageio-ffmpeg."
        )
    return ffmpeg


class DownloadEngine:
    """Reliable yt-dlp facade used by the desktop manager."""

    def __init__(
        self,
        output_dir: Path,
        progress: Callable[[dict], None] | None = None,
        *,
        skip_duplicates: bool = False,
    ):
        self.output_dir = Path(output_dir).expanduser()
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.progress = progress or (lambda _: None)
        self.skip_duplicates = skip_duplicates
        self._cancel_event = threading.Event()
        self._produced: list[Path] = []
        self._titles: list[str] = []

    # ------------------------------------------------------------------ opts
    def _common(self, *, playlist: bool = False) -> dict:
        opts: dict = {
            "noplaylist": not playlist,
            "quiet": True,
            "no_warnings": True,
            "noprogress": True,
            "restrictfilenames": False,
            "windowsfilenames": os.name == "nt",
            "continuedl": True,
            "overwrites": False,
            "retries": 10,
            "file_access_retries": 5,
            "fragment_retries": 10,
            "extractor_retries": 3,
            "socket_timeout": 30,
            "concurrent_fragment_downloads": 8,
            "ignoreerrors": False,
            "progress_hooks": [self._hook],
            "postprocessor_hooks": [self._pp_hook],
            "paths": {"home": str(self.output_dir)},
        }
        if self.skip_duplicates:
            opts["download_archive"] = str(self.output_dir / ".marqueslab-download-archive.txt")
        ffmpeg = ffmpeg_executable()
        if ffmpeg:
            # yt-dlp accepts either the directory or the binary itself; passing
            # the binary keeps a bundled FFmpeg working even when the directory
            # holds no ffprobe next to it.
            opts["ffmpeg_location"] = ffmpeg
            opts["prefer_ffmpeg"] = True
        return opts

    # ----------------------------------------------------------------- hooks
    def _check_cancelled(self) -> None:
        if self._cancel_event.is_set():
            raise DownloadCancelled("Download cancelado pelo usuário")

    def _hook(self, data: dict) -> None:
        self._check_cancelled()
        if data.get("status") == "finished":
            self._remember(data.get("info_dict") or {}, data.get("filename"))
        self.progress(data)

    def _pp_hook(self, data: dict) -> None:
        self._check_cancelled()
        if data.get("status") == "finished":
            self._remember(data.get("info_dict") or {})

    def _remember(self, info: dict, fallback: str | None = None) -> None:
        candidate = info.get("filepath") or info.get("_filename") or fallback
        title = info.get("title")
        if title and title not in self._titles:
            self._titles.append(title)
        if not candidate:
            return
        path = Path(candidate)
        if path not in self._produced:
            self._produced.append(path)

    # --------------------------------------------------------------- actions
    def analyze(self, url: str, *, playlist: bool = False) -> dict:
        url = normalize_url(url)
        opts = self._common(playlist=playlist) | {
            "skip_download": True,
            "extract_flat": "in_playlist" if playlist else False,
        }
        with yt_dlp.YoutubeDL(opts) as ydl:
            return ydl.extract_info(url, download=False)

    def build_options(self, choice: MediaChoice, *, playlist: bool = False) -> dict:
        opts = self._common(playlist=playlist) | {
            "format": choice.format_selector,
            "outtmpl": {"default": "%(title).160B [%(id)s].%(ext)s"},
        }
        if choice.mode == "video":
            opts["merge_output_format"] = "mp4"
            opts["postprocessors"] = [
                {"key": "FFmpegVideoRemuxer", "preferedformat": "mp4"},
            ]
        else:
            bitrate = choice.quality.split()[0]
            opts["postprocessors"] = [
                {
                    "key": "FFmpegExtractAudio",
                    "preferredcodec": "mp3",
                    "preferredquality": bitrate,
                },
                {"key": "FFmpegMetadata", "add_metadata": True},
            ]
            # yt-dlp matches postprocessor argument keys in lower case and
            # without the FFmpeg prefix; "FFmpegExtractAudio" is silently ignored.
            opts["postprocessor_args"] = {"extractaudio": ["-id3v2_version", "3"]}
        return opts

    def download(self, url: str, choice: MediaChoice, *, playlist: bool = False) -> DownloadResult:
        url = normalize_url(url)
        require_ffmpeg()
        self._cancel_event.clear()
        self._produced = []
        self._titles = []
        opts = self.build_options(choice, playlist=playlist)
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                retcode = ydl.download([url])
            if retcode:
                raise RuntimeError(f"yt-dlp finalizou com código {retcode}")
        except yt_dlp.utils.DownloadError as exc:
            if self._cancel_event.is_set():
                raise DownloadCancelled("Download cancelado pelo usuário") from exc
            raise
        finally:
            self._cancel_event.clear()
        files = [p for p in self._produced if p.exists()]
        return DownloadResult(files=files, titles=list(self._titles))

    def cancel(self) -> None:
        self._cancel_event.set()

    @property
    def cancelled(self) -> bool:
        return self._cancel_event.is_set()

    # ------------------------------------------------------------- summaries
    @staticmethod
    def summarize(info: dict) -> dict:
        formats = info.get("formats") or []
        heights = sorted({int(f["height"]) for f in formats if f.get("height")}, reverse=True)
        entries = info.get("entries") or []
        return {
            "title": info.get("title") or "Mídia sem título",
            "duration": info.get("duration"),
            "thumbnail": info.get("thumbnail"),
            "uploader": info.get("uploader") or info.get("channel"),
            "webpage_url": info.get("webpage_url") or info.get("original_url"),
            "max_height": heights[0] if heights else None,
            "heights": heights,
            "is_playlist": bool(info.get("_type") == "playlist" or entries),
            "entries": len(entries),
        }


def format_bytes(value: float | None) -> str:
    if not value:
        return "—"
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    size = float(value)
    for unit in units:
        if size < 1024 or unit == units[-1]:
            return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} B"
        size /= 1024
    return f"{size:.1f} TiB"


def format_duration(seconds: float | None) -> str:
    if not seconds:
        return "—"
    total = int(seconds)
    hours, rest = divmod(total, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{secs:02d}"
    return f"{minutes}:{secs:02d}"
