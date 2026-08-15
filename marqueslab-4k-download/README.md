# Marques Lab 4K Download

Desktop downloader/converter for media that the user is authorized to download.

## Highlights
- URL analysis with `yt-dlp` for publicly accessible sources.
- Force Download action: starts the best permitted format immediately after analysis.
- MP4 video up to 4K when the source actually exposes 2160p.
- MP3 extraction at high quality.
- HLS/DASH/direct media support through yt-dlp/FFmpeg when the source permits access.
- Queue, progress, cancel, retry and output folder selection.
- No Marques Lab account required.
- No cookies, credential capture, DRM bypass or authentication circumvention.
- macOS and Windows oriented.

## Requirements
- Python 3.11+
- FFmpeg available in PATH
- `pip install -r requirements.txt`

## Run
```bash
python -m app
```

## Diagnostics
```bash
python -m unittest discover -s tests -v
```

The diagnostic suite validates URL normalization, output naming, format selection and engine command construction without contacting a media provider.

## Legal/technical boundary
The app is intended for content the user owns or has permission to download, and for sources that permit downloading. It does not implement DRM cracking, login bypass, paywall circumvention, or extraction of credentials/session cookies.
