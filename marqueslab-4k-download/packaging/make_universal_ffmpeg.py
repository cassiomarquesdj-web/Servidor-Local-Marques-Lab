"""Create a Universal 2 FFmpeg binary from the published imageio-ffmpeg wheels.

imageio-ffmpeg ships one macOS binary per architecture. To produce a Universal 2
application the two binaries are downloaded and merged with `lipo`.

    python packaging/make_universal_ffmpeg.py build/ffmpeg-universal
"""
from __future__ import annotations

import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

PYPI_JSON = "https://pypi.org/pypi/imageio-ffmpeg/{version}/json"
MAC_WHEEL_MARKERS = ("macosx_11_0_arm64", "macosx_10_9_x86_64")


def installed_version() -> str:
    import imageio_ffmpeg

    return imageio_ffmpeg.__version__


def wheel_urls(version: str) -> dict[str, str]:
    import json

    with urllib.request.urlopen(PYPI_JSON.format(version=version), timeout=60) as response:
        payload = json.load(response)
    found: dict[str, str] = {}
    for item in payload["urls"]:
        for marker in MAC_WHEEL_MARKERS:
            if marker in item["filename"]:
                found[marker] = item["url"]
    missing = [m for m in MAC_WHEEL_MARKERS if m not in found]
    if missing:
        raise SystemExit(f"imageio-ffmpeg {version} não publica wheels para: {', '.join(missing)}")
    return found


def extract_ffmpeg(wheel: Path, destination: Path) -> Path:
    with zipfile.ZipFile(wheel) as archive:
        names = [n for n in archive.namelist() if "/binaries/ffmpeg-" in n and not n.endswith("/")]
        if not names:
            raise SystemExit(f"nenhum binário FFmpeg encontrado em {wheel.name}")
        name = names[0]
        destination.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(name) as source, destination.open("wb") as target:
            target.write(source.read())
    destination.chmod(0o755)
    return destination


def main() -> int:
    if sys.platform != "darwin":
        raise SystemExit("lipo só existe no macOS")
    output = Path(sys.argv[1] if len(sys.argv) > 1 else "build/ffmpeg-universal").resolve()
    work = output.parent / "ffmpeg-universal-work"
    work.mkdir(parents=True, exist_ok=True)

    version = installed_version()
    print(f"[universal-ffmpeg] imageio-ffmpeg {version}")
    slices: list[Path] = []
    for marker, url in wheel_urls(version).items():
        wheel = work / Path(url).name
        if not wheel.exists():
            print(f"[universal-ffmpeg] baixando {wheel.name}")
            urllib.request.urlretrieve(url, wheel)
        binary = extract_ffmpeg(wheel, work / f"ffmpeg-{marker}")
        print(f"[universal-ffmpeg] {marker}: {binary}")
        slices.append(binary)

    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["lipo", "-create", *[str(s) for s in slices], "-output", str(output)], check=True)
    output.chmod(0o755)
    info = subprocess.run(["lipo", "-info", str(output)], capture_output=True, text=True, check=True)
    print(f"[universal-ffmpeg] {info.stdout.strip()}")
    if "arm64" not in info.stdout or "x86_64" not in info.stdout:
        raise SystemExit("o binário resultante não é Universal 2")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
