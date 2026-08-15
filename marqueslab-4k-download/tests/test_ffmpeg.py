import unittest

from engine import ffmpeg_executable


class FFmpegTests(unittest.TestCase):
    def test_ffmpeg_is_discoverable(self):
        self.assertTrue(ffmpeg_executable(), "FFmpeg should be available in CI or the desktop environment")


if __name__ == "__main__":
    unittest.main()
