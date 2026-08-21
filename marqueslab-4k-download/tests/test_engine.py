import pytest

from engine import (
    VIDEO_QUALITIES, VIDEO_SELECTORS, video_selector, DownloadEngine, choose_audio, choose_video, format_bytes,
    format_duration, normalize_url, safe_filename, split_urls,
)


def test_normalize_url_trims():
    assert normalize_url(" https://example.com/video ") == "https://example.com/video"


@pytest.mark.parametrize("value", ["ftp://example.com/file", "example.com", "", "   ", "javascript:alert(1)"])
def test_reject_invalid_url(value):
    with pytest.raises(ValueError):
        normalize_url(value)


def test_safe_filename():
    assert safe_filename('A:/B*?C') == 'A__B__C'
    assert safe_filename("   ") == "MarquesLab_Media"
    assert len(safe_filename("x" * 500)) <= 180


def test_split_urls_deduplicates_and_preserves_order():
    urls = split_urls("https://example.com/a\nhttps://example.com/a\n\nhttps://example.com/b")
    assert urls == ["https://example.com/a", "https://example.com/b"]


def test_split_urls_rejects_garbage():
    with pytest.raises(ValueError):
        split_urls("https://example.com/a\nnot-a-url")


@pytest.mark.parametrize("quality,expected", [
    ("2160p", "height<=2160"),
    ("1440p", "height<=1440"),
    ("1080p", "height<=1080"),
    ("720p", "height<=720"),
])
def test_video_selectors(quality, expected):
    choice = choose_video(quality)
    assert expected in choice.format_selector
    assert choice.extension == "mp4"
    assert choice.mode == "video"


def test_unknown_quality_falls_back_to_best():
    assert choose_video("8000p").quality == "best"
    assert choose_video("best", editable=False).format_selector == VIDEO_SELECTORS["best"]


def test_editable_profile_asks_for_h264_and_aac_first():
    """Premiere and After Effects reject the AV1/Opus streams YouTube prefers."""
    choice = choose_video("1080p")
    assert choice.editable is True
    first_branch = choice.format_selector.split("/")[0]
    assert "vcodec^=avc1" in first_branch
    assert "acodec^=mp4a" in first_branch
    assert "height<=1080" in first_branch


def test_editable_profile_is_the_default():
    assert choose_video().editable is True
    assert choose_video("720p", editable=False).editable is False
    assert "avc1" not in choose_video("720p", editable=False).format_selector


def test_every_selector_ends_with_an_unconstrained_fallback():
    """A source with no declared height must still resolve to something."""
    for quality in VIDEO_QUALITIES:
        for editable in (True, False):
            assert video_selector(quality, editable=editable).split("/")[-1] == "best"


def test_audio_choice():
    choice = choose_audio()
    assert choice.mode == "audio"
    assert choice.extension == "mp3"
    assert "320" in choice.quality
    assert "bestaudio" in choice.format_selector


def test_summary_of_single_media():
    summary = DownloadEngine.summarize({
        "title": "Demo",
        "duration": 12,
        "uploader": "Marques Lab",
        "formats": [{"height": 1080}, {"height": 2160}, {"height": 720}],
        "webpage_url": "https://example.com/demo",
    })
    assert summary["title"] == "Demo"
    assert summary["max_height"] == 2160
    assert summary["heights"] == [2160, 1080, 720]
    assert summary["is_playlist"] is False
    assert summary["entries"] == 0


def test_summary_of_playlist():
    summary = DownloadEngine.summarize({
        "_type": "playlist",
        "title": "Set",
        "entries": [{"id": "a"}, {"id": "b"}],
    })
    assert summary["is_playlist"] is True
    assert summary["entries"] == 2
    assert summary["max_height"] is None


def test_audio_postprocessor_arguments_use_ytdlp_keys(tmp_path):
    """yt-dlp ignores postprocessor_args keyed by the class name."""
    engine = DownloadEngine(tmp_path)
    opts = engine.build_options(choose_audio())
    keys = [pp["key"] for pp in opts["postprocessors"]]
    assert "FFmpegExtractAudio" in keys
    assert set(opts["postprocessor_args"]) == {"extractaudio"}


def test_video_options_target_mp4(tmp_path):
    engine = DownloadEngine(tmp_path)
    opts = engine.build_options(choose_video("2160p"))
    assert opts["merge_output_format"] == "mp4"
    assert opts["noplaylist"] is True


def test_playlist_flag_enables_playlists(tmp_path):
    engine = DownloadEngine(tmp_path)
    assert engine.build_options(choose_video(), playlist=True)["noplaylist"] is False


def test_duplicate_archive_is_opt_in(tmp_path):
    """A download archive silently skips re-downloads; it must not be default."""
    assert "download_archive" not in DownloadEngine(tmp_path).build_options(choose_video())
    opts = DownloadEngine(tmp_path, skip_duplicates=True).build_options(choose_video())
    assert "download_archive" in opts


def test_output_directory_is_created(tmp_path):
    target = tmp_path / "nested" / "output"
    DownloadEngine(target)
    assert target.is_dir()


def test_format_helpers():
    assert format_bytes(None) == "—"
    assert format_bytes(512) == "512 B"
    assert format_bytes(1536).startswith("1.5 KiB")
    assert format_duration(None) == "—"
    assert format_duration(65) == "1:05"
    assert format_duration(3725) == "1:02:05"


def test_friendly_error_explains_a_403():
    """A raw 'HTTP Error 403' tells the user nothing about what to do."""
    from engine import friendly_error

    message = friendly_error("ERROR: unable to download video data: HTTP Error 403: Forbidden")
    assert "desatualizado" in message
    assert "Atualize" in message
    assert "Detalhe técnico:" in message
    assert "403" in message


@pytest.mark.parametrize("raw,expected", [
    ("ERROR: Requested format is not available", "Melhor disponível"),
    ("Sign in to confirm your age", "confirmação de idade"),
    ("ERROR: Private video. Sign in", "privada"),
    ("ERROR: Video unavailable", "não está disponível"),
    ("ERROR: Unsupported URL: https://example.com", "não é reconhecido"),
])
def test_friendly_error_covers_the_common_failures(raw, expected):
    from engine import friendly_error

    assert expected in friendly_error(raw)


def test_friendly_error_passes_unknown_messages_through():
    from engine import friendly_error

    assert friendly_error("  algo totalmente novo  ") == "algo totalmente novo"


def test_extractor_version_is_reported():
    from engine import extractor_version

    version = extractor_version()
    assert version and version[0].isdigit()
