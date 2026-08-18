from pathlib import Path


def test_download_contract():
    root = Path(__file__).resolve().parents[1]
    engine = root / "engine.py"
    assert engine.exists()
    text = engine.read_text(encoding="utf-8").lower()
    assert "ffmpeg" in text
    assert "yt-dlp" in text or "yt_dlp" in text
