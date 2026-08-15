from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable
from urllib.parse import urlparse
import re

import yt_dlp


@dataclass(frozen=True)
class MediaChoice:
    mode: str
    quality: str
    format_selector: str
    extension: str


def normalize_url(value: str) -> str:
    value = value.strip()
    if not value:
        raise ValueError("URL vazia")
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("Informe uma URL HTTP/HTTPS válida")
    return value


def safe_filename(name: str) -> str:
    name = re.sub(r"[\\/:*?\"<>|\x00-\x1f]", "_", name).strip(" .")
    return name[:180] or "MarquesLab_Media"


def choose_video(quality: str = "best") -> MediaChoice:
    if quality == "2160p":
        selector = "bestvideo[height<=2160]+bestaudio/best[height<=2160]"
    elif quality == "1440p":
        selector = "bestvideo[height<=1440]+bestaudio/best[height<=1440]"
    elif quality == "1080p":
        selector = "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
    else:
        selector = "bestvideo+bestaudio/best"
    return MediaChoice("video", quality, selector, "mp4")


def choose_audio() -> MediaChoice:
    return MediaChoice("audio", "high", "bestaudio/best", "mp3")


class DownloadEngine:
    def __init__(self, output_dir: Path, progress: Callable[[dict], None] | None = None):
        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.progress = progress or (lambda _: None)
        self._ydl: yt_dlp.YoutubeDL | None = None

    def _common(self) -> dict:
        return {
            "noplaylist": False,
            "quiet": True,
            "no_warnings": True,
            "restrictfilenames": False,
            "windowsfilenames": True,
            "continuedl": True,
            "retries": 5,
            "fragment_retries": 5,
            "concurrent_fragment_downloads": 4,
            "progress_hooks": [self._hook],
            # Deliberately do not load cookies or credentials.
            "cookiefile": None,
        }

    def _hook(self, data: dict) -> None:
        self.progress(data)

    def analyze(self, url: str) -> dict:
        url = normalize_url(url)
        opts = self._common() | {"skip_download": True}
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
        return info

    def download(self, url: str, choice: MediaChoice) -> None:
        url = normalize_url(url)
        opts = self._common() | {
            "format": choice.format_selector,
            "outtmpl": str(self.output_dir / "%(title).180B.%(ext)s"),
            "merge_output_format": "mp4" if choice.mode == "video" else None,
        }
        if choice.mode == "audio":
            opts["postprocessors"] = [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "320",
            }]
        with yt_dlp.YoutubeDL(opts) as ydl:
            self._ydl = ydl
            ydl.download([url])
            self._ydl = None

    def cancel(self) -> None:
        if self._ydl is not None:
            self._ydl._download_retcode = 1
            self._ydl = None
