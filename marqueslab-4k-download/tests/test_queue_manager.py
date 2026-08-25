"""Queue state machine of the desktop manager (headless Qt)."""
from __future__ import annotations

from pathlib import Path

import pytest

pytest.importorskip("PySide6")

from PySide6.QtWidgets import QApplication  # noqa: E402

import app as app_module  # noqa: E402
from app import JobStatus, MainWindow  # noqa: E402


@pytest.fixture(scope="module")
def qt_app():
    instance = QApplication.instance() or QApplication([])
    yield instance


@pytest.fixture
def window(qt_app, tmp_path, monkeypatch):
    monkeypatch.setattr(MainWindow, "_check_ffmpeg", lambda self: None)
    win = MainWindow()
    win.output_dir = tmp_path
    yield win
    win.close()


def add(window, *urls: str) -> None:
    window.url.setText("\n".join(urls))
    window.add_to_queue()


def test_multiple_urls_become_separate_jobs(window):
    add(window, "https://example.com/a", "https://example.com/b")
    assert [job.url for job in window.jobs] == ["https://example.com/a", "https://example.com/b"]
    assert window.queue.topLevelItemCount() == 2
    assert all(job.status is JobStatus.QUEUED for job in window.jobs)
    assert window.url.text() == ""


def test_duplicate_urls_in_one_paste_are_collapsed(window):
    add(window, "https://example.com/a", "https://example.com/a")
    assert len(window.jobs) == 1


def test_clear_completed_keeps_indexes_aligned(window):
    add(window, "https://example.com/a", "https://example.com/b", "https://example.com/c")
    window.jobs[0].status = JobStatus.DONE
    window.jobs[1].status = JobStatus.QUEUED
    window.jobs[2].status = JobStatus.FAILED
    window.clear_completed()

    assert [job.url for job in window.jobs] == ["https://example.com/b"]
    assert window.queue.topLevelItemCount() == 1
    assert len(window.items) == len(window.jobs)
    assert window.items[0].text(1) == "https://example.com/b"


def test_running_job_survives_clear_and_index_is_corrected(window):
    add(window, "https://example.com/a", "https://example.com/b", "https://example.com/c")
    window.jobs[0].status = JobStatus.DONE
    window.jobs[1].status = JobStatus.RUNNING
    window.active_index = 1
    window.clear_completed()

    assert window.jobs[window.active_index].url == "https://example.com/b"
    assert window.jobs[window.active_index].status is JobStatus.RUNNING


def test_remove_selected_never_drops_the_active_job(window):
    add(window, "https://example.com/a", "https://example.com/b")
    window.jobs[0].status = JobStatus.RUNNING
    window.active_index = 0
    window.queue.selectAll()
    window.remove_selected()

    assert [job.url for job in window.jobs] == ["https://example.com/a"]
    assert window.active_index == 0


def test_retry_requeues_only_failed_or_cancelled(window, monkeypatch):
    started: list[int] = []
    monkeypatch.setattr(MainWindow, "_start_job", lambda self, index: started.append(index))
    add(window, "https://example.com/a", "https://example.com/b", "https://example.com/c")
    window.jobs[0].status = JobStatus.DONE
    window.jobs[1].status = JobStatus.FAILED
    window.jobs[2].status = JobStatus.CANCELLED
    window.queue.selectAll()
    window.retry_selected()

    assert window.jobs[0].status is JobStatus.DONE
    assert window.jobs[1].status is JobStatus.QUEUED
    assert window.jobs[2].status is JobStatus.QUEUED
    assert started == [1]


def test_start_queue_picks_the_first_pending_job(window, monkeypatch):
    started: list[int] = []
    monkeypatch.setattr(MainWindow, "_start_job", lambda self, index: started.append(index))
    add(window, "https://example.com/a", "https://example.com/b")
    window.jobs[0].status = JobStatus.DONE
    window.start_queue()
    assert started == [1]


def test_start_queue_is_idle_when_nothing_pending(window, monkeypatch):
    started: list[int] = []
    monkeypatch.setattr(MainWindow, "_start_job", lambda self, index: started.append(index))
    add(window, "https://example.com/a")
    window.jobs[0].status = JobStatus.DONE
    window.start_queue()
    assert started == []
    assert "concluído" in window.info.text().lower()


def test_progress_updates_the_row(window):
    add(window, "https://example.com/a")
    window.active_index = 0
    window.jobs[0].status = JobStatus.RUNNING
    window.on_progress({
        "status": "downloading",
        "downloaded_bytes": 512_000,
        "total_bytes": 1_024_000,
        "speed": 2 * 1024 * 1024,
        "eta": 30,
        "info_dict": {"title": "Mídia de teste"},
    })
    assert window.jobs[0].percent == 50
    assert window.items[0].text(3) == "50%"
    assert "MiB/s" in window.items[0].text(4)
    assert window.items[0].text(1) == "Mídia de teste"


def test_audio_mode_disables_quality_selector(window):
    window.mode.setCurrentIndex(1)
    assert window.quality.isEnabled() is False
    assert window._choice().mode == "audio"
    window.mode.setCurrentIndex(0)
    assert window.quality.isEnabled() is True
    assert window._choice().mode == "video"


def test_quality_selector_maps_to_engine_presets(window):
    window.mode.setCurrentIndex(0)
    for index, expected in enumerate(["best", "2160p", "1440p", "1080p", "720p"]):
        window.quality.setCurrentIndex(index)
        assert window._choice().quality == expected


def test_history_is_persisted_to_the_output_folder(window, tmp_path):
    window._save_history("https://example.com/a", "concluído", "Mídia")
    assert window.history_file.exists()
    assert "concluído" in window.history.toPlainText()


def test_constructor_never_reads_the_protected_output_folder(qt_app, monkeypatch):
    """macOS blocks the first read of ~/Downloads on a TCC prompt.

    Doing it while building the window froze the app in the open() syscall with
    no window at all — indistinguishable from a launch failure.
    """
    reads: list[str] = []
    original = Path.read_text

    def spy(self, *args, **kwargs):
        reads.append(str(self))
        return original(self, *args, **kwargs)

    monkeypatch.setattr(MainWindow, "_check_ffmpeg", lambda self: None)
    monkeypatch.setattr(Path, "read_text", spy)
    win = MainWindow()
    try:
        assert not [r for r in reads if "marqueslab-history" in r], (
            f"o construtor leu a pasta protegida: {reads}"
        )
    finally:
        win.close()


def test_history_loads_asynchronously(window, tmp_path, qt_app):
    import json

    from app import read_history

    window.output_dir = tmp_path
    window.history_file.write_text(
        json.dumps([{"date": "2026-08-24 10:00", "status": "concluído",
                     "url": "https://example.com/a", "title": "Mídia"}]),
        encoding="utf-8",
    )
    assert "concluído" in read_history(window.history_file)

    window._load_history()
    assert window._history_thread is not None, "a leitura precisa sair da thread principal"
    for _ in range(100):
        qt_app.processEvents()
        if window._history_thread is None:
            break
    assert "concluído" in window.history.toPlainText()


def test_invalid_url_does_not_enqueue(window, monkeypatch):
    warnings: list[str] = []
    monkeypatch.setattr(app_module.QMessageBox, "warning", lambda *args: warnings.append(args[-1]))
    window.url.setText("nao-e-url")
    window.add_to_queue()
    assert window.jobs == []
    assert warnings


def test_editable_checkbox_is_on_by_default_and_reaches_the_engine(window):
    assert window.editable.isChecked() is True
    assert window._choice().editable is True
    assert "vcodec^=avc1" in window._choice().format_selector

    window.editable.setChecked(False)
    assert window._choice().editable is False
    assert "vcodec^=avc1" not in window._choice().format_selector


def test_editable_checkbox_only_applies_to_video(window):
    window.mode.setCurrentIndex(1)
    assert window.editable.isEnabled() is False
    window.mode.setCurrentIndex(0)
    assert window.editable.isEnabled() is True


def test_queue_row_shows_the_profile(window):
    window.editable.setChecked(True)
    window.quality.setCurrentIndex(3)
    window.url.setText("https://example.com/a")
    window.add_to_queue()
    assert window.items[0].text(2) == "MP4 • 1080p • H.264"


def test_conversion_progress_is_reported_in_the_queue(window):
    window.url.setText("https://example.com/a")
    window.add_to_queue()
    window.active_index = 0
    window.jobs[0].status = JobStatus.RUNNING
    window.on_progress({"status": "converting", "percent": 42, "conversion": "video"})

    assert window.jobs[0].status is JobStatus.CONVERTING
    assert window.items[0].text(3) == "42%"
    assert "Premiere" in window.info.text()

    window.on_progress({"status": "converted", "percent": 100})
    assert window.jobs[0].status is JobStatus.RUNNING
    assert window.jobs[0].percent == 100


def test_browser_session_defaults_to_none(window):
    assert window._browser_session() is None
    assert window.browser.currentIndex() == 0


def test_browser_session_reaches_the_worker(window):
    from app import BROWSER_SESSIONS

    index = next(i for i, (_, key) in enumerate(BROWSER_SESSIONS) if key == "firefox")
    window.browser.setCurrentIndex(index)
    assert window._browser_session() == "firefox"
    assert "Chaveiro" in window.session_hint.text()

    window.browser.setCurrentIndex(0)
    assert window._browser_session() is None
    assert "público" in window.session_hint.text()


def test_silent_result_is_marked_in_the_queue(window, monkeypatch):
    from engine import DownloadResult

    shown: list[str] = []
    monkeypatch.setattr(app_module.QMessageBox, "warning", lambda *a: shown.append(a[-1]))
    window.url.setText("https://www.instagram.com/reel/abc/")
    window.add_to_queue()
    window.active_index = 0
    monkeypatch.setattr(MainWindow, "_next_or_finish", lambda self: None)

    window.on_finished(DownloadResult(files=[], titles=["Reel"], warnings=["\"reel.mp4\" foi baixado SEM faixa de áudio."]))

    assert window.items[0].text(0) == "⚠️ Sem áudio"
    assert shown, "o usuário precisa ser avisado do vídeo mudo"


def test_window_is_placed_on_a_visible_screen(window):
    """A window opened on a disconnected or unattended monitor reads as a crash."""
    assert window._visible_on_some_screen()


def test_offscreen_geometry_is_recovered(window, qt_app):
    """The bug: Qt placed the window on a second monitor at negative coordinates."""
    window.move(-4000, -3000)
    assert not window._visible_on_some_screen()

    window.center_on_primary()
    assert window._visible_on_some_screen()

    area = qt_app.primaryScreen().availableGeometry()
    assert area.contains(window.frameGeometry().center())


def test_geometry_is_persisted_on_close(window):
    window.settings.remove("geometry")
    window.close()
    assert window.settings.value("geometry") is not None


def test_restore_ignores_geometry_that_is_no_longer_visible(window, qt_app):
    window.move(-4000, -3000)
    window.settings.setValue("geometry", window.saveGeometry())
    window._restore_geometry()
    assert window._visible_on_some_screen()


def test_ensure_visible_runs_after_show_and_recovers_the_window(window, qt_app):
    """The real bug: the check ran before show(), when geometry is a placeholder."""
    window.show()
    window.move(-4000, -3000)
    assert not window._visible_on_some_screen()

    window.ensure_visible()

    assert window._visible_on_some_screen()
    area = qt_app.primaryScreen().availableGeometry()
    assert area.contains(window.frameGeometry().center())


def test_ensure_visible_leaves_a_good_position_alone(window, qt_app):
    window.show()
    window.center_on_primary()
    before = window.frameGeometry()
    window.ensure_visible()
    assert window.frameGeometry() == before


def test_fresh_profile_centers_on_the_primary_screen(qt_app, tmp_path, monkeypatch):
    monkeypatch.setattr(MainWindow, "_check_ffmpeg", lambda self: None)
    fresh = MainWindow()
    fresh.settings.remove("geometry")
    try:
        fresh._restore_geometry()
        area = qt_app.primaryScreen().availableGeometry()
        assert area.contains(fresh.frameGeometry().center())
    finally:
        fresh.close()


def test_history_never_lives_in_the_protected_output_folder(window, tmp_path):
    """~/Downloads is TCC-gated: the first access blocks the calling thread."""
    window.output_dir = tmp_path
    assert tmp_path not in window.history_file.parents
    assert "Application Support" in str(window.history_file)


def test_saving_history_does_not_touch_the_output_folder(window, tmp_path, monkeypatch):
    touched: list[str] = []
    original_mkdir = Path.mkdir

    def spy(self, *args, **kwargs):
        touched.append(str(self))
        return original_mkdir(self, *args, **kwargs)

    window.output_dir = tmp_path / "saida"
    monkeypatch.setattr(Path, "mkdir", spy)
    window._save_history("https://example.com/a", "concluído", "Mídia")

    assert not [t for t in touched if "saida" in t]
    assert "concluído" in window.history.toPlainText()


def test_open_folder_does_not_mkdir_on_the_ui_thread(window, tmp_path, monkeypatch):
    import threading

    main = threading.current_thread()
    on_main: list[str] = []
    original = Path.mkdir

    def spy(self, *args, **kwargs):
        if threading.current_thread() is main:
            on_main.append(str(self))
        return original(self, *args, **kwargs)

    monkeypatch.setattr(Path, "mkdir", spy)
    window.output_dir = tmp_path / "inexistente"
    window.open_folder()

    assert not [c for c in on_main if "inexistente" in c], (
        "mkdir em pasta protegida na thread da interface trava a janela"
    )
    assert "Preparando" in window.info.text()
