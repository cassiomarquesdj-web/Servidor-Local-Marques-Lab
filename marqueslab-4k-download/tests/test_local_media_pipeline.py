from pathlib import Path
import subprocess


def test_local_mp4_and_mp3_pipeline(tmp_path: Path):
    video = tmp_path / "fixture.mp4"
    audio = tmp_path / "fixture.mp3"
    subprocess.run([
        "ffmpeg", "-y", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=10",
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "1",
        "-c:v", "libx264", "-c:a", "aac", str(video)
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([
        "ffmpeg", "-y", "-i", str(video), "-vn", "-c:a", "libmp3lame", "-b:a", "320k", str(audio)
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert video.stat().st_size > 0
    assert audio.stat().st_size > 0
