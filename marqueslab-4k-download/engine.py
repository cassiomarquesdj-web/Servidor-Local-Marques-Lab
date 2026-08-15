from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable
from urllib.parse import urlparse
import re
import shutil
import sys
import threading

import yt_dlp

try:
    import imageio_ffmpeg
except ImportError:  # pragma: no cover
    imageio_ffmpeg = None


@dataclass(frozen=True)
class MediaChoice:
    mode: str
    quality: str
    format_selector: str
    extension: str


class DownloadCancelled(Exception):
    """Raised internally when the user cancels an active download."""


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
    for raw in re.split(r"[\r\n]+", value):
        raw = raw.strip()
        if not raw:
            continue
        urls.append(normalize_url(raw))
    return list(dict.fromkeys(urls))


def safe_filename(name: str) -> str:
    name = re.sub(r"[\\/:*?\"<>|\x00-\x1f]", "_", name).strip(" .")
    return name[:180] or "MarquesLab_Media"


def choose_video(quality: str = "best") -> MediaChoice:
    selectors = {
        "2160p": "bestvideo[height<=2160]+bestaudio/best[height<=2160]",
        "1440p": "bestvideo[height<=1440]+bestaudio/best[height<=1440]",
        "1080p": "bestvideo[height<=1080]+bestaudio/best[height<=1080]",
        "720p": "bestvideo[height<=720]+bestaudio/best[height<=720]",
        "best": "bestvideo+bestaudio/best",
    }
    quality = quality if quality in selectors else "best"
    return MediaChoice("video", quality, selectors[quality], "mp4")


def choose_audio() -> MediaChoice:
    return MediaChoice("audio", "320 kbps", "bestaudio/best", "mp3")


def ffmpeg_executable() -> str | None:
    if getattr(sys, "frozen", False):
        root = Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent))
        for name in ("ffmpeg", "ffmpeg.exe"):
            bundled = root / name
            if bundled.exists():
                return str(bundled)
    if imageio_ffmpeg is not None:
        try:
            return imageio_ffmpeg.get_ffmpeg_exe()
        except Exception:
            pass
    return shutil.which("ffmpeg")


class DownloadEngine:
    """Reliable yt-dlp facade used by the desktop manager.

    The engine deliberately delegates access control to the source/provider. It does
    not accept credentials, cookies, DRM bypasses or authentication circumvention.
    """

    def __init__(self, output_dir: Path, progress: Callable[[dict], None] | None = None):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.progress = progress or (lambda _: None)
        self._ydl: yt_dlp.YoutubeDL | None = None
        self._cancel_event = threading.Event()

    def _common(self, *, playlist: bool = False) -> dict:
        archive = self.output_dir / ".marqueslab-download-archive.txt"
        opts: dict = {
            "noplaylist": not playlist,
            "quiet": True,
            "no_warnings": True,
            "restrictfilenames": False,
            "windowsfilenames": True,
            "continuedl": True,
            "overwrites": False,
            "nooverwrites": True,
            "retries": 10,
            "file_access_retries": 5,
            "fragment_retries": 10,
            "socket_timeout": 30,
            "concurrent_fragment_downloads": 8,
            "sleep_interval": 0,
            "download_archive": str(archive),
            "progress_hooks": [self._hook],
            "cookiefile": None,
            "cachedir": True,
        }
        ffmpeg = ffmpeg_executable()
        if ffmpeg:
            opts["ffmpeg_location"] = str(Path(ffmpeg).parent)
            opts["prefer_ffmpeg"] = True
        return opts

    def _hook(self, data: dict) -> None:
        if self._cancel_event.is_set():
            raise DownloadCancelled("Download cancelado pelo usuário")
        self.progress(data)

    def analyze(self, url: str, *, playlist: bool = False) -> dict:
        url = normalize_url(url)
        opts = self._common(playlist=playlist) | {"skip_download": True}
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
        return info

    def download(self, url: str, choice: MediaChoice, *, playlist: bool = False) -> None:
        url = normalize_url(url)
        self._cancel_event.clear()
        opts = self._common(playlist=playlist) | {
            "format": choice.format_selector,
            "outtmpl": str(self.output_dir / "%(title).160B [%(id)s].%(ext)s"),
            "merge_output_format": "mp4" if choice.mode == "video" else None,
            "postprocessor_args": {"merger": ["-movflags", "+faststart"]},
        }
        if choice.mode == "audio":
            opts["postprocessors"] = [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "320",
            }]
            opts["postprocessor_args"] = {"FFmpegExtractAudio": ["-id3v2_version", "3"]}
        with yt_dlp.YoutubeDL(opts) as ydl:
            self._ydl = ydl
            try:
                ydl.download([url])
            finally:
                self._ydl = None
                self._cancel_event.clear()

    def cancel(self) -> None:
        self._cancel_event.set()
        if self._ydl is not None:
            self._ydl._download_retcode = 1

    @staticmethod
    def summarize(info: dict) -> dict:
        formats = info.get("formats") or []
        heights = sorted({int(f["height"]) for f in formats if f.get("height")}, reverse=True)
        return {
            "title": info.get("title") or "Mídia sem título",
            "duration": info.get("duration"),
            "thumbnail": info.get("thumbnail"),
            "uploader": info.get("uploader") or info.get("channel"),
            "webpage_url": info.get("webpage_url") or info.get("original_url"),
            "max_height": heights[0] if heights else None,
            "heights": heights,
            "is_playlist": bool(info.get("_type") == "playlist" or info.get("entries")),
            "entries": len(info.get("entries") or []) if info.get("entries") else 0,
        }
