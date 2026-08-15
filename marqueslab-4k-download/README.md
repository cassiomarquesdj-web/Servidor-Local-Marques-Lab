# Marques Lab 4K Download

Desktop media download manager focused on **speed, reliability, queue control and a premium native desktop workflow** for media the user is authorized to download.

## Current product direction

The goal is not to be a thin wrapper around `yt-dlp`. Marques Lab 4K Download is being built as a real download manager:

- **Smart queue** with sequential processing, cancel, retry-friendly resume and persistent history.
- **Multi-URL input**: paste several URLs at once or drag links into the application.
- **4K / 1440p / 1080p / 720p** selection when the source exposes those qualities.
- **MP3 320 kbps** extraction with FFmpeg metadata processing.
- **Force Download** for the fastest path from URL to the selected output.
- **Provider analysis** showing title, uploader, duration, maximum available height and playlist information.
- **Duplicate protection** using a persistent download archive and collision-safe filenames.
- **Resumable downloads** with retries, fragment retries and concurrent fragment downloading.
- **Bundled FFmpeg** in frozen macOS builds, so the application does not depend on a system FFmpeg installation.
- **Native macOS DMG builds** for Apple Silicon and Intel.
- **Persistent preferences** for output folder and a local history of recent jobs.
- **No account required** for the application itself.

## Reliability principles

The engine uses `yt-dlp` and FFmpeg as implementation components while keeping the application layer responsible for queue management, UX, state and reliability. Downloads are configured to continue partial files, avoid accidental overwrites, retry transient failures and keep an archive of completed items.

The application intentionally does **not** capture credentials/cookies or implement DRM cracking, login bypass, paywall circumvention, or authentication circumvention. It is intended for content the user owns or has permission to download and for sources that permit downloading.

## Requirements for source development

- Python 3.11+
- FFmpeg available in PATH for source runs (frozen macOS builds bundle FFmpeg)
- `pip install -r requirements.txt`

## Run

```bash
python -m app
```

## Tests

```bash
python -m unittest discover -s tests -v
```

The CI also runs an actual local FFmpeg fixture pipeline to catch missing media-engine dependencies before a release build.

## Release target

The release gate is intentionally strict:

1. Unit tests pass.
2. FFmpeg integration passes.
3. PyInstaller package starts/smoke-tests.
4. DMG is created and validated.
5. Apple Silicon and Intel artifacts are available.

Only after those gates pass should a build be considered release-ready.
