from pathlib import Path


def test_project_has_expected_download_contract():
    root = Path(__file__).resolve().parents[1]
    engine = root / "engine.py"
    assert engine.exists(), "engine.py missing"
    text = engine.read_text(encoding="utf-8")
    assert "yt-dlp" in text or "yt_dlp" in text
    assert "ffmpeg" in text.lower()
