import unittest
from pathlib import Path

from engine import choose_audio, choose_video, normalize_url, safe_filename


class EngineTests(unittest.TestCase):
    def test_normalize_url(self):
        self.assertEqual(normalize_url(" https://example.com/video "), "https://example.com/video")

    def test_reject_invalid_url(self):
        with self.assertRaises(ValueError):
            normalize_url("ftp://example.com/file")

    def test_safe_filename(self):
        self.assertEqual(safe_filename('A:/B*?C'), 'A__B__C')

    def test_4k_selector(self):
        choice = choose_video("2160p")
        self.assertIn("height<=2160", choice.format_selector)
        self.assertEqual(choice.extension, "mp4")

    def test_audio_selector(self):
        choice = choose_audio()
        self.assertEqual(choice.mode, "audio")
        self.assertEqual(choice.extension, "mp3")


if __name__ == "__main__":
    unittest.main()
