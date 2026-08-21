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
import subprocess
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


VIDEO_QUALITIES: tuple[str, ...] = ("best", "2160p", "1440p", "1080p", "720p")

# Codecs that Premiere Pro and After Effects open natively. YouTube's "best"
# streams are AV1 or VP9 with Opus audio: they play fine in a browser and are
# rejected by both editors, which is why the editable profile is the default.
EDITABLE_VIDEO_CODECS = frozenset({"h264"})
EDITABLE_AUDIO_CODECS = frozenset({"aac"})

_STREAM_LINE = re.compile(r"Stream #\d+:\d+.*?: (Video|Audio): (\w+)")
_DURATION_LINE = re.compile(r"Duration: (\d+):(\d+):(\d+\.\d+)")
_PROGRESS_TIME = re.compile(r"out_time_ms=(\d+)")


def _height_filter(quality: str) -> str:
    return "" if quality == "best" else f"[height<={quality.rstrip('p')}]"


def video_selector(quality: str, *, editable: bool) -> str:
    """Build the yt-dlp format selector for a quality preset.

    When `editable` is set the selector asks for H.264 video and AAC audio
    first, which YouTube serves up to 1080p. That avoids re-encoding entirely
    for the common case — the file arrives already editable and untouched.
    """
    height = _height_filter(quality)
    # The trailing bare "best" matters: sources that expose a single stream with
    # no declared height (a direct .mp4 link, for instance) are filtered out by
    # every height-constrained branch and would otherwise fail outright.
    fallback = f"bestvideo{height}+bestaudio/best{height}/best"
    if not editable:
        return fallback
    return (
        f"bestvideo[vcodec^=avc1]{height}+bestaudio[acodec^=mp4a]/"
        f"bestvideo[vcodec^=avc1]{height}+bestaudio/"
        f"best[vcodec^=avc1]{height}/"
        f"{fallback}"
    )


VIDEO_SELECTORS: dict[str, str] = {
    quality: video_selector(quality, editable=False) for quality in VIDEO_QUALITIES
}


@dataclass(frozen=True)
class MediaChoice:
    mode: str
    quality: str
    format_selector: str
    extension: str
    editable: bool = False


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


def choose_video(quality: str = "best", *, editable: bool = True) -> MediaChoice:
    """Pick a video profile.

    `editable=True` guarantees a file Premiere Pro and After Effects can open:
    H.264 video with AAC audio, converted with the bundled FFmpeg only when the
    source has nothing compatible to offer (YouTube has no H.264 above 1080p).
    """
    quality = quality if quality in VIDEO_QUALITIES else "best"
    return MediaChoice("video", quality, video_selector(quality, editable=editable), "mp4", editable)


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
        if choice.mode == "video" and choice.editable:
            files = [
                ensure_editable(path, self.progress, self._cancel_event.is_set)
                for path in files
            ]
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


# Mapping of the failures users actually hit, to a message that says what to do.
# yt-dlp's raw text ("HTTP Error 403: Forbidden") tells a user nothing about the
# fact that the provider changed its delivery and the extractor is out of date.
_FRIENDLY_ERRORS: tuple[tuple[str, str], ...] = (
    (
        "403",
        "A fonte recusou a entrega da mídia (HTTP 403). Isso quase sempre "
        "significa que o site mudou a forma de servir o vídeo e o extrator "
        "embarcado ficou desatualizado. Atualize o Marques Lab 4K Download "
        "para a versão mais recente.",
    ),
    (
        "requested format is not available",
        "A qualidade escolhida não existe para esta mídia. Selecione "
        "\"Melhor disponível\" ou uma resolução menor e tente novamente.",
    ),
    (
        "sign in to confirm your age",
        "Esta mídia exige confirmação de idade na fonte. O aplicativo não faz "
        "login nem contorna restrição de acesso.",
    ),
    (
        "private video",
        "Esta mídia é privada. O aplicativo não faz login nem contorna "
        "restrição de acesso.",
    ),
    (
        "video unavailable",
        "A fonte informou que esta mídia não está disponível.",
    ),
    (
        "unsupported url",
        "Este site não é reconhecido pelo extrator embarcado.",
    ),
    (
        "name or service not known",
        "Sem conexão com a internet ou o endereço não pôde ser resolvido.",
    ),
)


def probe_media(path: Path) -> tuple[str | None, str | None, float | None]:
    """Return (video codec, audio codec, duration) using FFmpeg alone.

    ffprobe is deliberately not required: the distributed application bundles
    FFmpeg only, so every media inspection must work with that single binary.
    """
    ffmpeg = require_ffmpeg()
    result = subprocess.run(
        [ffmpeg, "-hide_banner", "-i", str(path)],
        capture_output=True, text=True,
    )
    banner = result.stderr
    video = audio = None
    for kind, codec in _STREAM_LINE.findall(banner):
        if kind == "Video" and video is None:
            video = codec
        elif kind == "Audio" and audio is None:
            audio = codec
    duration = None
    match = _DURATION_LINE.search(banner)
    if match:
        hours, minutes, seconds = match.groups()
        duration = int(hours) * 3600 + int(minutes) * 60 + float(seconds)
    return video, audio, duration


def _h264_encoder(ffmpeg: str) -> list[str]:
    """Prefer Apple's hardware encoder: ~2.5x faster than libx264 on Apple Silicon."""
    encoders = subprocess.run(
        [ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True
    ).stdout
    if "h264_videotoolbox" in encoders:
        return ["-c:v", "h264_videotoolbox", "-profile:v", "high", "-q:v", "65"]
    return ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-profile:v", "high"]


def ensure_editable(
    path: Path,
    progress: Callable[[dict], None] | None = None,
    cancelled: Callable[[], bool] | None = None,
) -> Path:
    """Guarantee that `path` opens in Premiere Pro and After Effects.

    Streams that are already H.264/AAC are copied instead of re-encoded, so a
    file that only has the wrong audio costs seconds rather than minutes.
    """
    video, audio, duration = probe_media(path)
    video_ok = video in EDITABLE_VIDEO_CODECS
    audio_ok = audio in EDITABLE_AUDIO_CODECS or audio is None
    if video_ok and audio_ok:
        return path

    ffmpeg = require_ffmpeg()
    # The output container must be MP4: WebM only accepts VP8/VP9/AV1 with
    # Vorbis/Opus, so writing H.264/AAC into the source extension fails outright.
    final = path.with_suffix(".mp4")
    target = path.with_name(f"{path.stem}.editavel.mp4")
    command = [ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-i", str(path)]
    command += ["-c:v", "copy"] if video_ok else _h264_encoder(ffmpeg)
    if not video_ok:
        command += ["-pix_fmt", "yuv420p"]
    command += ["-c:a", "copy"] if audio_ok else ["-c:a", "aac", "-b:a", "320k"]
    command += ["-movflags", "+faststart", "-progress", "pipe:1", "-nostats", str(target)]

    report = progress or (lambda _: None)
    report({
        "status": "converting",
        "info_dict": {"filepath": str(path)},
        "conversion": "video" if not video_ok else "audio",
        "percent": 0,
    })

    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        for line in process.stdout or ():
            if cancelled and cancelled():
                process.kill()
                raise DownloadCancelled("Conversão cancelada pelo usuário")
            match = _PROGRESS_TIME.search(line)
            if match and duration:
                done = int(match.group(1)) / 1_000_000
                report({
                    "status": "converting",
                    "info_dict": {"filepath": str(path)},
                    "conversion": "video" if not video_ok else "audio",
                    "percent": max(0, min(100, int(done * 100 / duration))),
                })
        process.wait()
    finally:
        if process.poll() is None:
            process.kill()

    if process.returncode != 0:
        target.unlink(missing_ok=True)
        raise RuntimeError(
            "Falha ao converter a mídia para H.264/AAC: "
            + (process.stderr.read().strip() if process.stderr else "erro desconhecido")
        )

    path.unlink(missing_ok=True)
    target.replace(final)
    report({"status": "converted", "info_dict": {"filepath": str(final)}, "percent": 100})
    return final


def friendly_error(message: str) -> str:
    """Translate a yt-dlp failure into something the user can act on."""
    lowered = message.lower()
    for needle, explanation in _FRIENDLY_ERRORS:
        if needle in lowered:
            return f"{explanation}\n\nDetalhe técnico: {message.strip()}"
    return message.strip()


def extractor_version() -> str:
    """Version of the bundled yt-dlp, shown in the About dialog and self-test."""
    return yt_dlp.version.__version__


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
