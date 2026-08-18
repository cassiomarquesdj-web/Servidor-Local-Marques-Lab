"""Queue state machine of the desktop manager (headless Qt)."""
from __future__ import annotations

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


def test_invalid_url_does_not_enqueue(window, monkeypatch):
    warnings: list[str] = []
    monkeypatch.setattr(app_module.QMessageBox, "warning", lambda *args: warnings.append(args[-1]))
    window.url.setText("nao-e-url")
    window.add_to_queue()
    assert window.jobs == []
    assert warnings
