"""Marques Lab 4K Download — desktop media download manager."""
from __future__ import annotations

import json
import platform
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path

from PySide6 import QtCore
from PySide6.QtCore import QObject, QSettings, Qt, QThread, QUrl, Signal, Slot
from PySide6.QtGui import QAction, QDesktopServices, QDragEnterEvent, QDropEvent, QIcon
from PySide6.QtWidgets import (
    QAbstractItemView, QApplication, QCheckBox, QComboBox, QFileDialog,
    QGroupBox, QHBoxLayout, QHeaderView, QLabel, QLineEdit, QMainWindow,
    QMessageBox, QPlainTextEdit, QProgressBar, QPushButton, QSplitter,
    QTreeWidget, QTreeWidgetItem, QVBoxLayout, QWidget,
)

from branding import APP_NAME, BUNDLE_ID, COPYRIGHT, ORGANIZATION, VERSION
from engine import (
    DownloadCancelled, DownloadEngine, DownloadResult, FFmpegNotFound, MediaChoice,
    choose_audio, choose_video, extractor_version, ffmpeg_executable, format_bytes,
    format_duration, friendly_error, split_urls,
)

ICON_PATH = Path(__file__).resolve().parent / "assets" / "AppIcon.icns"


class JobStatus(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"
    CANCELLED = "cancelled"


STATUS_LABEL = {
    JobStatus.QUEUED: "⏳ Na fila",
    JobStatus.RUNNING: "🔄 Baixando",
    JobStatus.DONE: "✅ Concluído",
    JobStatus.FAILED: "❌ Falhou",
    JobStatus.CANCELLED: "⏹ Cancelado",
}

COLUMNS = ["Status", "Mídia", "Formato", "Progresso", "Velocidade"]


@dataclass
class QueueJob:
    url: str
    choice: MediaChoice
    playlist: bool = False
    title: str = ""
    status: JobStatus = JobStatus.QUEUED
    percent: int = 0
    speed: str = "—"
    message: str = ""
    files: list[Path] = field(default_factory=list)

    @property
    def display_title(self) -> str:
        return self.title or self.url

    @property
    def format_label(self) -> str:
        if self.choice.mode == "audio":
            return f"MP3 • {self.choice.quality}"
        return f"MP4 • {self.choice.quality}"

    @property
    def is_pending(self) -> bool:
        return self.status is JobStatus.QUEUED

    @property
    def is_finished(self) -> bool:
        return self.status in {JobStatus.DONE, JobStatus.FAILED, JobStatus.CANCELLED}


class AnalyzeWorker(QObject):
    """Resolves media metadata off the UI thread."""

    done = Signal(dict)
    failed = Signal(str)

    def __init__(self, url: str, output: Path, playlist: bool):
        super().__init__()
        self.url = url
        self.output = output
        self.playlist = playlist

    @Slot()
    def run(self):
        try:
            engine = DownloadEngine(self.output)
            info = engine.analyze(self.url, playlist=self.playlist)
            self.done.emit(engine.summarize(info))
        except Exception as exc:  # noqa: BLE001 - surfaced to the user
            self.failed.emit(friendly_error(str(exc)))


class DownloadWorker(QObject):
    progress = Signal(dict)
    finished = Signal(object)
    cancelled = Signal()
    failed = Signal(str)

    def __init__(self, job: QueueJob, output: Path):
        super().__init__()
        self.job = job
        self.output = output
        self.engine: DownloadEngine | None = None

    @Slot()
    def run(self):
        try:
            self.engine = DownloadEngine(self.output, self.progress.emit)
            result = self.engine.download(self.job.url, self.job.choice, playlist=self.job.playlist)
            self.finished.emit(result)
        except DownloadCancelled:
            self.cancelled.emit()
        except Exception as exc:  # noqa: BLE001 - surfaced to the user
            self.failed.emit(friendly_error(str(exc)))

    def cancel(self):
        if self.engine:
            self.engine.cancel()


class DropLineEdit(QLineEdit):
    dropped = Signal(str)

    def __init__(self):
        super().__init__()
        self.setAcceptDrops(True)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls() or event.mimeData().hasText():
            event.acceptProposedAction()

    def dropEvent(self, event: QDropEvent):
        urls = [u.toString() for u in event.mimeData().urls()]
        text = "\n".join(urls) if urls else event.mimeData().text()
        self.dropped.emit(text)
        event.acceptProposedAction()


def reveal_in_file_manager(path: Path) -> None:
    """Open the platform file manager with `path` selected."""
    if not path.exists():
        return
    system = platform.system()
    if system == "Darwin":
        subprocess.run(["open", "-R", str(path)], check=False)
    elif system == "Windows":
        subprocess.run(["explorer", "/select,", str(path)], check=False)
    else:
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(path.parent)))


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.settings = QSettings(ORGANIZATION, APP_NAME)
        default_output = Path.home() / "Downloads" / APP_NAME
        self.output_dir = Path(self.settings.value("output", str(default_output)))
        self.jobs: list[QueueJob] = []
        self.items: list[QTreeWidgetItem] = []
        self.active_index = -1
        self._thread: QThread | None = None
        self._worker: DownloadWorker | None = None
        self._analyze_thread: QThread | None = None
        self._analyze_worker: AnalyzeWorker | None = None
        self._shutting_down = False
        self.setWindowTitle(APP_NAME)
        self.resize(1180, 800)
        self._build()
        self._build_menu()
        self._check_ffmpeg()

    # ---------------------------------------------------------------- layout
    def _build(self):
        root = QWidget()
        root_layout = QVBoxLayout(root)
        root_layout.setSpacing(12)
        root_layout.setContentsMargins(18, 16, 18, 14)

        title = QLabel(APP_NAME.upper())
        title.setObjectName("title")
        subtitle = QLabel("Gerenciador profissional de mídia • 4K • MP4 • MP3 320 kbps • fila inteligente")
        subtitle.setObjectName("subtitle")
        root_layout.addWidget(title)
        root_layout.addWidget(subtitle)

        input_box = QGroupBox("Adicionar downloads")
        input_layout = QVBoxLayout(input_box)
        row = QHBoxLayout()
        self.url = DropLineEdit()
        self.url.setPlaceholderText("Cole uma ou várias URLs — uma por linha — ou arraste links aqui")
        row.addWidget(self.url, 1)
        self.analyze_btn = QPushButton("ANALISAR")
        self.add_btn = QPushButton("ADICIONAR À FILA")
        self.force_btn = QPushButton("BAIXAR AGORA")
        self.force_btn.setObjectName("primary")
        row.addWidget(self.analyze_btn)
        row.addWidget(self.add_btn)
        row.addWidget(self.force_btn)
        input_layout.addLayout(row)
        self.analysis = QLabel("Nenhuma mídia analisada.")
        self.analysis.setWordWrap(True)
        self.analysis.setObjectName("analysis")
        input_layout.addWidget(self.analysis)
        root_layout.addWidget(input_box)

        options = QHBoxLayout()
        self.mode = QComboBox()
        self.mode.addItems(["MP4 • Vídeo", "MP3 • Áudio"])
        self.quality = QComboBox()
        self.quality.addItems(["Melhor disponível", "2160p • 4K", "1440p", "1080p", "720p"])
        self.playlist = QCheckBox("Baixar playlist quando a fonte oferecer")
        self.folder_btn = QPushButton("PASTA DE SAÍDA")
        self.open_folder_btn = QPushButton("ABRIR PASTA")
        options.addWidget(QLabel("Formato:"))
        options.addWidget(self.mode)
        options.addWidget(QLabel("Qualidade:"))
        options.addWidget(self.quality)
        options.addWidget(self.playlist)
        options.addStretch(1)
        options.addWidget(self.folder_btn)
        options.addWidget(self.open_folder_btn)
        root_layout.addLayout(options)

        split = QSplitter(Qt.Vertical)
        queue_box = QGroupBox("Fila de downloads")
        queue_layout = QVBoxLayout(queue_box)
        self.queue = QTreeWidget()
        self.queue.setHeaderLabels(COLUMNS)
        self.queue.setRootIsDecorated(False)
        self.queue.setAlternatingRowColors(True)
        self.queue.setSelectionMode(QAbstractItemView.ExtendedSelection)
        header = self.queue.header()
        header.setSectionResizeMode(0, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(4, QHeaderView.ResizeToContents)
        queue_layout.addWidget(self.queue)

        controls = QHBoxLayout()
        self.start_btn = QPushButton("INICIAR FILA")
        self.start_btn.setObjectName("primary")
        self.cancel_btn = QPushButton("CANCELAR ATUAL")
        self.retry_btn = QPushButton("TENTAR NOVAMENTE")
        self.remove_btn = QPushButton("REMOVER SELECIONADOS")
        self.clear_btn = QPushButton("LIMPAR CONCLUÍDOS")
        for button in (self.start_btn, self.cancel_btn, self.retry_btn, self.remove_btn, self.clear_btn):
            controls.addWidget(button)
        controls.addStretch(1)
        queue_layout.addLayout(controls)
        split.addWidget(queue_box)

        history_box = QGroupBox("Histórico recente")
        history_layout = QVBoxLayout(history_box)
        self.history = QPlainTextEdit()
        self.history.setReadOnly(True)
        self.history.setMaximumHeight(150)
        history_layout.addWidget(self.history)
        split.addWidget(history_box)
        split.setStretchFactor(0, 3)
        split.setStretchFactor(1, 1)
        root_layout.addWidget(split, 1)

        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.setFormat("%p%")
        self.info = QLabel(f"Pronto • Saída: {self.output_dir}")
        self.info.setObjectName("status")
        root_layout.addWidget(self.progress)
        root_layout.addWidget(self.info)

        self.setCentralWidget(root)
        self.setStyleSheet(STYLESHEET)

        self.url.dropped.connect(self.url.setText)
        self.url.returnPressed.connect(self.add_to_queue)
        self.analyze_btn.clicked.connect(self.analyze)
        self.add_btn.clicked.connect(self.add_to_queue)
        self.force_btn.clicked.connect(self.download_now)
        self.start_btn.clicked.connect(self.start_queue)
        self.cancel_btn.clicked.connect(self.cancel_current)
        self.retry_btn.clicked.connect(self.retry_selected)
        self.remove_btn.clicked.connect(self.remove_selected)
        self.clear_btn.clicked.connect(self.clear_completed)
        self.folder_btn.clicked.connect(self.choose_folder)
        self.open_folder_btn.clicked.connect(self.open_folder)
        self.mode.currentIndexChanged.connect(self._sync_quality)
        self.queue.itemDoubleClicked.connect(self._reveal_item)
        self._load_history()
        self._sync_quality()

    def _build_menu(self):
        menu = self.menuBar()
        file_menu = menu.addMenu("Arquivo")
        act_folder = QAction("Escolher pasta de saída…", self)
        act_folder.triggered.connect(self.choose_folder)
        act_open = QAction("Abrir pasta de saída", self)
        act_open.triggered.connect(self.open_folder)
        file_menu.addAction(act_folder)
        file_menu.addAction(act_open)

        queue_menu = menu.addMenu("Fila")
        for label, slot in (
            ("Iniciar fila", self.start_queue),
            ("Cancelar download atual", self.cancel_current),
            ("Tentar novamente", self.retry_selected),
            ("Remover selecionados", self.remove_selected),
            ("Limpar concluídos", self.clear_completed),
        ):
            action = QAction(label, self)
            action.triggered.connect(slot)
            queue_menu.addAction(action)

        help_menu = menu.addMenu("Ajuda")
        about = QAction(f"Sobre o {APP_NAME}", self)
        about.triggered.connect(self.show_about)
        help_menu.addAction(about)

    def show_about(self):
        ffmpeg = ffmpeg_executable() or "não encontrado"
        QMessageBox.information(
            self,
            f"Sobre o {APP_NAME}",
            f"<b>{APP_NAME}</b><br>Versão {VERSION}<br>{COPYRIGHT}<br><br>"
            f"Identificador: {BUNDLE_ID}<br>"
            f"Extrator yt-dlp: {extractor_version()}<br>FFmpeg: {ffmpeg}",
        )

    def _check_ffmpeg(self):
        if not ffmpeg_executable():
            self.info.setText("FFmpeg não encontrado — conversões MP3 e junção 4K indisponíveis.")
            QMessageBox.warning(
                self,
                "FFmpeg",
                "FFmpeg não foi encontrado neste ambiente. A versão distribuída do "
                f"{APP_NAME} inclui FFmpeg; ao executar a partir do código-fonte, "
                "instale o FFmpeg ou o pacote imageio-ffmpeg.",
            )

    # --------------------------------------------------------------- helpers
    def _sync_quality(self):
        self.quality.setEnabled(self.mode.currentIndex() == 0)

    def _choice(self) -> MediaChoice:
        if self.mode.currentIndex() == 1:
            return choose_audio()
        labels = {0: "best", 1: "2160p", 2: "1440p", 3: "1080p", 4: "720p"}
        return choose_video(labels[self.quality.currentIndex()])

    def _urls(self) -> list[str]:
        return split_urls(self.url.text())

    def _refresh_row(self, index: int):
        job = self.jobs[index]
        item = self.items[index]
        item.setText(0, STATUS_LABEL[job.status])
        item.setText(1, job.display_title)
        item.setToolTip(1, f"{job.url}\n{job.message}".strip())
        item.setText(2, job.format_label)
        item.setText(3, f"{job.percent}%")
        item.setText(4, job.speed)

    def _running(self) -> bool:
        return self._thread is not None and self._thread.isRunning()

    # ---------------------------------------------------------------- actions
    def choose_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Escolha a pasta de saída", str(self.output_dir))
        if folder:
            self.output_dir = Path(folder)
            self.settings.setValue("output", str(self.output_dir))
            self.info.setText(f"Saída: {self.output_dir}")
            self._load_history()

    def open_folder(self):
        self.output_dir.mkdir(parents=True, exist_ok=True)
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.output_dir)))

    def analyze(self):
        if self._analyze_thread and self._analyze_thread.isRunning():
            return
        try:
            urls = self._urls()
        except ValueError as exc:
            QMessageBox.warning(self, "Análise", str(exc))
            return
        if not urls:
            QMessageBox.warning(self, "Análise", "Cole pelo menos uma URL.")
            return
        self.analysis.setText("Analisando fonte…")
        self.analyze_btn.setEnabled(False)
        self._analyze_thread = QThread(self)
        self._analyze_worker = AnalyzeWorker(urls[0], self.output_dir, self.playlist.isChecked())
        self._analyze_worker.moveToThread(self._analyze_thread)
        self._analyze_thread.started.connect(self._analyze_worker.run)
        self._analyze_worker.done.connect(self._on_analysis)
        self._analyze_worker.failed.connect(self._on_analysis_failed)
        self._analyze_thread.start()

    def _stop_analysis(self):
        if self._analyze_thread:
            self._analyze_thread.quit()
            self._analyze_thread.wait(3000)
        self._analyze_thread = None
        self._analyze_worker = None
        self.analyze_btn.setEnabled(True)

    @Slot(dict)
    def _on_analysis(self, info: dict):
        quality = f"até {info['max_height']}p" if info["max_height"] else "qualidade não informada"
        extra = f" • {info['entries']} itens" if info["is_playlist"] else ""
        duration = f" • {format_duration(info['duration'])}" if info["duration"] else ""
        uploader = f" • {info['uploader']}" if info["uploader"] else ""
        self.analysis.setText(f"{info['title']} • {quality}{duration}{uploader}{extra}")
        self._stop_analysis()

    @Slot(str)
    def _on_analysis_failed(self, message: str):
        self.analysis.setText("Não foi possível analisar esta fonte.")
        self._stop_analysis()
        QMessageBox.warning(self, "Análise", message)

    def _append_job(self, url: str):
        job = QueueJob(url=url, choice=self._choice(), playlist=self.playlist.isChecked())
        item = QTreeWidgetItem(["", "", "", "", ""])
        self.jobs.append(job)
        self.items.append(item)
        self.queue.addTopLevelItem(item)
        self._refresh_row(len(self.jobs) - 1)

    def add_to_queue(self):
        try:
            urls = self._urls()
        except ValueError as exc:
            QMessageBox.warning(self, "Fila", str(exc))
            return
        if not urls:
            QMessageBox.warning(self, "Fila", "Cole pelo menos uma URL.")
            return
        for url in urls:
            self._append_job(url)
        self.url.clear()
        self.info.setText(f"{len(urls)} item(ns) adicionado(s) à fila.")

    def download_now(self):
        before = len(self.jobs)
        self.add_to_queue()
        if len(self.jobs) > before:
            self.start_queue()

    def start_queue(self):
        if self._running():
            return
        index = next((i for i, job in enumerate(self.jobs) if job.is_pending), None)
        if index is None:
            self.info.setText("Fila vazia ou todos os itens já concluídos.")
            return
        self._start_job(index)

    def _start_job(self, index: int):
        self.active_index = index
        job = self.jobs[index]
        job.status = JobStatus.RUNNING
        job.percent = 0
        job.speed = "—"
        self._refresh_row(index)
        self.progress.setValue(0)
        self.info.setText(f"Baixando {index + 1}/{len(self.jobs)} — {job.display_title}")
        self._thread = QThread(self)
        self._worker = DownloadWorker(job, self.output_dir)
        self._worker.moveToThread(self._thread)
        self._thread.started.connect(self._worker.run)
        self._worker.progress.connect(self.on_progress)
        self._worker.finished.connect(self.on_finished)
        self._worker.cancelled.connect(self.on_cancelled)
        self._worker.failed.connect(self.on_failed)
        self._thread.start()

    def _cleanup_thread(self):
        if self._thread:
            self._thread.quit()
            self._thread.wait(5000)
        self._worker = None
        self._thread = None

    @Slot(dict)
    def on_progress(self, data: dict):
        if self.active_index < 0:
            return
        job = self.jobs[self.active_index]
        info = data.get("info_dict") or {}
        if not job.title and info.get("title"):
            job.title = info["title"]
        total = data.get("total_bytes") or data.get("total_bytes_estimate")
        done = data.get("downloaded_bytes") or 0
        if total:
            job.percent = max(0, min(100, int(done * 100 / total)))
            self.progress.setValue(job.percent)
        speed = data.get("speed")
        job.speed = f"{speed / 1024 / 1024:.1f} MiB/s" if speed else "—"
        eta = data.get("eta")
        detail = f"{format_bytes(done)} de {format_bytes(total)}" if total else format_bytes(done)
        eta_text = f" • ETA {format_duration(eta)}" if eta else ""
        self.info.setText(f"Baixando {job.display_title} • {detail} • {job.speed}{eta_text}")
        self._refresh_row(self.active_index)

    def _next_or_finish(self):
        self._cleanup_thread()
        self.active_index = -1
        if self._shutting_down:
            return
        index = next((i for i, job in enumerate(self.jobs) if job.is_pending), None)
        if index is not None:
            self._start_job(index)
        else:
            self.progress.setValue(0)
            self.info.setText(f"Fila concluída • {self.output_dir}")

    @Slot(object)
    def on_finished(self, result: DownloadResult):
        index = self.active_index
        if index >= 0:
            job = self.jobs[index]
            job.status = JobStatus.DONE
            job.percent = 100
            job.speed = "—"
            job.files = list(result.files)
            if result.titles and not job.title:
                job.title = result.titles[0]
            job.message = "\n".join(str(p) for p in job.files)
            self._refresh_row(index)
            self.progress.setValue(100)
            self._save_history(job.url, "concluído", job.display_title)
        self._next_or_finish()

    @Slot()
    def on_cancelled(self):
        index = self.active_index
        if index >= 0:
            job = self.jobs[index]
            job.status = JobStatus.CANCELLED
            job.speed = "—"
            self._refresh_row(index)
            self._save_history(job.url, "cancelado", job.display_title)
        self._next_or_finish()

    @Slot(str)
    def on_failed(self, message: str):
        index = self.active_index
        if index >= 0:
            job = self.jobs[index]
            job.status = JobStatus.FAILED
            job.speed = "—"
            job.message = message
            self._refresh_row(index)
            self._save_history(job.url, "falhou: " + message[:160], job.display_title)
        if not self._shutting_down:
            box = QMessageBox(self)
            box.setIcon(QMessageBox.Warning)
            box.setWindowTitle("Download")
            head, _, detail = message.partition("Detalhe técnico:")
            box.setText(head.strip() or message)
            if detail:
                box.setDetailedText(detail.strip())
            box.exec()
        self._next_or_finish()

    def cancel_current(self):
        if self._worker:
            self.info.setText("Cancelando…")
            self._worker.cancel()

    def _selected_indexes(self) -> list[int]:
        selected = set(self.queue.selectedItems())
        return [i for i, item in enumerate(self.items) if item in selected]

    def retry_selected(self):
        indexes = [i for i in self._selected_indexes() if self.jobs[i].status in {JobStatus.FAILED, JobStatus.CANCELLED}]
        if not indexes:
            self.info.setText("Selecione itens que falharam ou foram cancelados para tentar novamente.")
            return
        for i in indexes:
            job = self.jobs[i]
            job.status = JobStatus.QUEUED
            job.percent = 0
            job.message = ""
            self._refresh_row(i)
        self.info.setText(f"{len(indexes)} item(ns) recolocado(s) na fila.")
        self.start_queue()

    def _drop_rows(self, indexes: list[int]) -> int:
        removed = 0
        for i in sorted(indexes, reverse=True):
            if i == self.active_index:
                continue
            item = self.items.pop(i)
            self.jobs.pop(i)
            self.queue.takeTopLevelItem(self.queue.indexOfTopLevelItem(item))
            if self.active_index > i:
                self.active_index -= 1
            removed += 1
        return removed

    def remove_selected(self):
        removed = self._drop_rows(self._selected_indexes())
        self.info.setText(
            f"{removed} item(ns) removido(s) da fila." if removed
            else "Nada removido. O item em download não pode ser removido — cancele antes."
        )

    def clear_completed(self):
        removed = self._drop_rows([i for i, job in enumerate(self.jobs) if job.is_finished])
        self.info.setText(f"{removed} item(ns) concluído(s) removido(s) da tela. Histórico preservado.")

    def _reveal_item(self, item: QTreeWidgetItem):
        try:
            index = self.items.index(item)
        except ValueError:
            return
        job = self.jobs[index]
        if job.files:
            reveal_in_file_manager(job.files[0])
        elif job.status is JobStatus.FAILED and job.message:
            QMessageBox.information(self, "Detalhes do erro", job.message)

    # --------------------------------------------------------------- history
    @property
    def history_file(self) -> Path:
        return self.output_dir / ".marqueslab-history.json"

    def _load_history(self):
        try:
            data = json.loads(self.history_file.read_text(encoding="utf-8"))
            lines = [f"{x['date']} • {x['status']} • {x.get('title') or x['url']}" for x in data[-30:]]
            self.history.setPlainText("\n".join(reversed(lines)))
        except Exception:  # noqa: BLE001 - history is best effort
            self.history.clear()

    def _save_history(self, url: str, status: str, title: str = ""):
        try:
            data = []
            if self.history_file.exists():
                data = json.loads(self.history_file.read_text(encoding="utf-8"))
            data.append({
                "date": datetime.now().strftime("%Y-%m-%d %H:%M"),
                "url": url,
                "title": title,
                "status": status,
            })
            self.output_dir.mkdir(parents=True, exist_ok=True)
            self.history_file.write_text(
                json.dumps(data[-200:], ensure_ascii=False, indent=2), encoding="utf-8"
            )
            self._load_history()
        except Exception:  # noqa: BLE001 - history is best effort
            pass

    def closeEvent(self, event):
        self._shutting_down = True
        if self._worker:
            self._worker.cancel()
        self._cleanup_thread()
        self._stop_analysis()
        event.accept()


STYLESHEET = """
QWidget { background:#0d0f12; color:#f4f5f7; font-size:14px; }
QMainWindow::separator { background:#2c3037; }
QGroupBox { border:1px solid #2c3037; border-radius:10px; margin-top:12px; padding:14px; font-weight:700; }
QGroupBox::title { subcontrol-origin: margin; left:12px; padding:0 6px; color:#c8ccd4; }
QLineEdit, QComboBox, QPlainTextEdit, QTreeWidget { background:#171a1f; border:1px solid #30343b; border-radius:7px; padding:8px; }
QTreeWidget { alternate-background-color:#13161c; outline:0; }
QTreeWidget::item { padding:6px 4px; color:#f4f5f7; }
QTreeWidget::item:selected { background:#2a3a55; }
QHeaderView::section { background:#171a1f; color:#aeb5c0; border:0; border-bottom:1px solid #30343b; padding:7px; font-weight:700; }
QPushButton { background:#242830; border:1px solid #424852; border-radius:7px; padding:10px 15px; font-weight:800; }
QPushButton:hover { background:#303640; }
QPushButton:disabled { color:#6b7078; border-color:#2b2f36; }
QPushButton#primary { background:#1d5fd0; border-color:#2f74ea; }
QPushButton#primary:hover { background:#2670e8; }
QProgressBar { border:1px solid #30343b; border-radius:6px; text-align:center; background:#171a1f; height:22px; }
QProgressBar::chunk { background:#1d5fd0; border-radius:5px; }
QCheckBox { spacing:8px; }
#title { font-size:28px; font-weight:900; padding-top:4px; letter-spacing:1px; }
#subtitle { color:#aeb5c0; }
#analysis { color:#c8ccd4; }
#status { color:#aeb5c0; }
"""


def _download_self_test(ffmpeg: str) -> str:
    """Download and convert real media using only what ships inside the app.

    A short clip is rendered by the bundled FFmpeg, served over loopback HTTP and
    pulled back through the download engine as MP3. It proves the distributed
    application works on a machine with no Python, FFmpeg or yt-dlp installed.
    """
    import tempfile
    import threading
    from functools import partial
    from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
    from urllib.parse import quote

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        source = root / "MarquesLab SelfTest.mp4"
        subprocess.run(
            [
                ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
                "-f", "lavfi", "-i", "testsrc=size=320x240:rate=15",
                "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
                "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                "-c:a", "aac", str(source),
            ],
            check=True,
        )

        class Quiet(SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Quiet, directory=str(root)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_address[1]}/{quote(source.name)}"
            engine = DownloadEngine(root / "out")
            result = engine.download(url, choose_audio())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        mp3 = next((f for f in result.files if f.suffix == ".mp3"), None)
        if not mp3 or not mp3.exists() or mp3.stat().st_size == 0:
            raise RuntimeError(f"o download real não produziu MP3 (arquivos: {result.files})")
        probe = subprocess.run([ffmpeg, "-hide_banner", "-i", str(mp3), "-f", "null", "-"],
                               capture_output=True, text=True)
        if probe.returncode != 0 or "Audio: mp3" not in probe.stderr:
            raise RuntimeError("o MP3 gerado não é reproduzível")
        return f"MP3 real gerado ({mp3.stat().st_size} bytes)"


def self_test(deep: bool = False) -> int:
    """Headless verification used to smoke-test the packaged application.

    Runs inside the frozen .app during the release pipeline: it proves that the
    bundle can start Qt, import the engine and execute the FFmpeg binary that
    ships inside the app — without any user-installed dependency.
    """
    import os

    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    checks: list[tuple[str, str]] = []

    app = QApplication.instance() or QApplication([])
    app.setApplicationName(APP_NAME)
    checks.append(("qt", f"PySide6 {QtCore.qVersion()}"))

    ffmpeg = ffmpeg_executable()
    if not ffmpeg:
        print("SELF-TEST FALHOU: FFmpeg não encontrado dentro do aplicativo", file=sys.stderr)
        return 1
    checks.append(("ffmpeg_path", ffmpeg))

    probe = subprocess.run([ffmpeg, "-version"], capture_output=True, text=True)
    if probe.returncode != 0:
        print(f"SELF-TEST FALHOU: FFmpeg não executou ({probe.returncode})", file=sys.stderr)
        return 1
    checks.append(("ffmpeg_version", probe.stdout.splitlines()[0]))

    import yt_dlp

    checks.append(("yt_dlp", yt_dlp.version.__version__))
    checks.append(("frozen", str(bool(getattr(sys, "frozen", False)))))

    window = MainWindow()
    window.close()
    checks.append(("window", "ok"))

    if deep:
        checks.append(("download", _download_self_test(ffmpeg)))

    print(f"SELF-TEST {APP_NAME} {VERSION}")
    for key, value in checks:
        print(f"  {key}: {value}")
    print("SELF-TEST: PASS")
    return 0


def main() -> int:
    flags = sys.argv[1:]
    if "--self-test" in flags or "--self-test-download" in flags:
        try:
            return self_test(deep="--self-test-download" in flags)
        except Exception as exc:  # noqa: BLE001 - reported to the release pipeline
            print(f"SELF-TEST FALHOU: {exc}", file=sys.stderr)
            return 1
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setApplicationDisplayName(APP_NAME)
    app.setOrganizationName(ORGANIZATION)
    app.setApplicationVersion(VERSION)
    if ICON_PATH.exists():
        app.setWindowIcon(QIcon(str(ICON_PATH)))
    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
