import sys
import unittest
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_DIR))

from engine import choose_audio, choose_video, normalize_url, safe_filename, split_urls, DownloadEngine


class EngineTests(unittest.TestCase):
    def test_normalize_url(self):
        self.assertEqual(normalize_url(" https://example.com/video "), "https://example.com/video")

    def test_reject_invalid_url(self):
        with self.assertRaises(ValueError):
            normalize_url("ftp://example.com/file")

    def test_safe_filename(self):
        self.assertEqual(safe_filename('A:/B*?C'), 'A__B__C')

    def test_split_urls_deduplicates(self):
        urls = split_urls("https://example.com/a\nhttps://example.com/a\nhttps://example.com/b")
        self.assertEqual(urls, ["https://example.com/a", "https://example.com/b"])

    def test_4k_selector(self):
        choice = choose_video("2160p")
        self.assertIn("height<=2160", choice.format_selector)
        self.assertEqual(choice.extension, "mp4")

    def test_audio_selector(self):
        choice = choose_audio()
        self.assertEqual(choice.mode, "audio")
        self.assertEqual(choice.extension, "mp3")
        self.assertIn("bestaudio", choice.format_selector)

    def test_summary(self):
        summary = DownloadEngine.summarize({
            "title": "Demo",
            "duration": 12,
            "uploader": "Marques Lab",
            "formats": [{"height": 1080}, {"height": 2160}, {"height": 720}],
            "webpage_url": "https://example.com/demo",
        })
        self.assertEqual(summary["title"], "Demo")
        self.assertEqual(summary["max_height"], 2160)
        self.assertEqual(summary["heights"], [2160, 1080, 720])
        self.assertFalse(summary["is_playlist"])


if __name__ == "__main__":
    unittest.main()
