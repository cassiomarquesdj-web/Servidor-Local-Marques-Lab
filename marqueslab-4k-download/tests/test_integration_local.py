from pathlib import Path
import subprocess


def test_ffmpeg_can_generate_and_probe_mp4(tmp_path: Path):
    out = tmp_path / "fixture.mp4"
    subprocess.run(
        [
            "ffmpeg", "-y", "-f", "lavfi", "-i", "testsrc=size=640x360:rate=25",
            "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=44100",
            "-t", "1", "-c:v", "libx264", "-c:a", "aac", str(out)
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    assert out.exists() and out.stat().st_size > 0
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(out)], capture_output=True, text=True, check=True)
    assert float(probe.stdout.strip()) > 0


def test_ffmpeg_extracts_mp3(tmp_path: Path):
    src = tmp_path / "fixture.mp4"
    mp3 = tmp_path / "fixture.mp3"
    subprocess.run(
        ["ffmpeg", "-y", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "1", "-c:a", "aac", str(src)],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(src), "-vn", "-c:a", "libmp3lame", "-b:a", "320k", str(mp3)],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    assert mp3.exists() and mp3.stat().st_size > 0
