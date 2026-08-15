from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import QObject, QThread, QSettings, Signal, Slot, Qt
from PySide6.QtGui import QDesktopServices, QDragEnterEvent, QDropEvent
from PySide6.QtCore import QUrl
from PySide6.QtWidgets import (
    QApplication, QFileDialog, QComboBox, QCheckBox, QHBoxLayout, QLabel,
    QLineEdit, QListWidget, QListWidgetItem, QMainWindow, QMessageBox,
    QProgressBar, QPushButton, QVBoxLayout, QWidget, QGroupBox, QFormLayout,
    QSplitter, QPlainTextEdit
)

from engine import DownloadCancelled, DownloadEngine, choose_audio, choose_video, normalize_url, split_urls


@dataclass
class QueueJob:
    url: str
    choice: object
    playlist: bool = False
    title: str = "Aguardando análise"


class DownloadWorker(QObject):
    progress = Signal(dict)
    finished = Signal()
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
            self.engine.download(self.job.url, self.job.choice, playlist=self.job.playlist)
            self.finished.emit()
        except DownloadCancelled:
            self.cancelled.emit()
        except Exception as exc:
            self.failed.emit(str(exc))

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


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.settings = QSettings("MarquesLab", "4KDownload")
        self.output_dir = Path(self.settings.value("output", str(Path.home() / "Downloads" / "Marques Lab 4K Download")))
        self.jobs: list[QueueJob] = []
        self.items: list[QListWidgetItem] = []
        self.active_index = -1
        self._thread: QThread | None = None
        self._worker: DownloadWorker | None = None
        self.setWindowTitle("Marques Lab 4K Download")
        self.resize(1120, 760)
        self._build()

    def _build(self):
        root = QWidget()
        root_layout = QVBoxLayout(root)
        root_layout.setSpacing(12)

        title = QLabel("MARQUES LAB 4K DOWNLOAD")
        title.setObjectName("title")
        subtitle = QLabel("Gerenciador profissional de mídia • 4K • MP4 • MP3 • fila inteligente")
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
        row.addWidget(self.analyze_btn)
        row.addWidget(self.add_btn)
        row.addWidget(self.force_btn)
        input_layout.addLayout(row)
        self.analysis = QLabel("Nenhuma mídia analisada.")
        self.analysis.setWordWrap(True)
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
        self.queue = QListWidget()
        queue_layout.addWidget(self.queue)
        controls = QHBoxLayout()
        self.start_btn = QPushButton("INICIAR FILA")
        self.cancel_btn = QPushButton("CANCELAR ATUAL")
        self.clear_btn = QPushButton("LIMPAR CONCLUÍDOS")
        controls.addWidget(self.start_btn)
        controls.addWidget(self.cancel_btn)
        controls.addWidget(self.clear_btn)
        controls.addStretch(1)
        queue_layout.addLayout(controls)
        split.addWidget(queue_box)

        history_box = QGroupBox("Histórico recente")
        history_layout = QVBoxLayout(history_box)
        self.history = QPlainTextEdit()
        self.history.setReadOnly(True)
        self.history.setMaximumHeight(140)
        history_layout.addWidget(self.history)
        split.addWidget(history_box)
        root_layout.addWidget(split, 1)

        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        self.progress.setFormat("%p%")
        self.info = QLabel(f"Pronto • Saída: {self.output_dir}")
        root_layout.addWidget(self.progress)
        root_layout.addWidget(self.info)

        self.setCentralWidget(root)
        self.setStyleSheet("""
            QWidget { background:#0d0f12; color:#f4f5f7; font-size:14px; }
            QGroupBox { border:1px solid #2c3037; border-radius:10px; margin-top:10px; padding:12px; font-weight:700; }
            QGroupBox::title { subcontrol-origin: margin; left:12px; padding:0 6px; }
            QLineEdit, QComboBox, QListWidget, QPlainTextEdit { background:#171a1f; border:1px solid #30343b; border-radius:7px; padding:9px; }
            QPushButton { background:#242830; border:1px solid #424852; border-radius:7px; padding:10px 15px; font-weight:800; }
            QPushButton:hover { background:#303640; }
            QPushButton:disabled { color:#777; }
            QProgressBar { border:1px solid #30343b; border-radius:6px; text-align:center; background:#171a1f; height:22px; }
            #title { font-size:28px; font-weight:900; padding-top:5px; }
            #subtitle { color:#aeb5c0; }
        """)

        self.url.dropped.connect(self.url.setText)
        self.analyze_btn.clicked.connect(self.analyze)
        self.add_btn.clicked.connect(self.add_to_queue)
        self.force_btn.clicked.connect(self.download_now)
        self.start_btn.clicked.connect(self.start_queue)
        self.cancel_btn.clicked.connect(self.cancel_current)
        self.clear_btn.clicked.connect(self.clear_completed)
        self.folder_btn.clicked.connect(self.choose_folder)
        self.open_folder_btn.clicked.connect(self.open_folder)
        self.mode.currentIndexChanged.connect(self._sync_quality)
        self._load_history()
        self._sync_quality()

    def _sync_quality(self):
        self.quality.setEnabled(self.mode.currentIndex() == 0)

    def choose_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Escolha a pasta de saída", str(self.output_dir))
        if folder:
            self.output_dir = Path(folder)
            self.settings.setValue("output", str(self.output_dir))
            self.info.setText(f"Saída: {self.output_dir}")

    def open_folder(self):
        self.output_dir.mkdir(parents=True, exist_ok=True)
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.output_dir)))

    def _choice(self):
        if self.mode.currentIndex() == 1:
            return choose_audio()
        labels = {0: "best", 1: "2160p", 2: "1440p", 3: "1080p", 4: "720p"}
        return choose_video(labels[self.quality.currentIndex()])

    def _urls(self) -> list[str]:
        try:
            return split_urls(self.url.text())
        except ValueError as exc:
            raise ValueError(str(exc))

    def analyze(self):
        try:
            urls = self._urls()
            if not urls:
                raise ValueError("Cole pelo menos uma URL.")
            self.analysis.setText("Analisando fonte…")
            engine = DownloadEngine(self.output_dir)
            info = engine.summarize(engine.analyze(urls[0], playlist=self.playlist.isChecked()))
            quality = f"até {info['max_height']}p" if info["max_height"] else "qualidade não informada"
            extra = f" • {info['entries']} itens" if info["is_playlist"] else ""
            duration = f" • {info['duration']}s" if info["duration"] else ""
            uploader = f" • {info['uploader']}" if info["uploader"] else ""
            self.analysis.setText(f"{info['title']} • {quality}{duration}{uploader}{extra}")
        except Exception as exc:
            QMessageBox.warning(self, "Análise", str(exc))

    def _append_job(self, url: str):
        job = QueueJob(url=url, choice=self._choice(), playlist=self.playlist.isChecked())
        self.jobs.append(job)
        item = QListWidgetItem(f"⏳ {job.choice.mode.upper()} • {url}")
        item.setData(Qt.UserRole, len(self.jobs) - 1)
        self.items.append(item)
        self.queue.addItem(item)

    def add_to_queue(self):
        try:
            urls = self._urls()
            if not urls:
                raise ValueError("Cole pelo menos uma URL.")
            for url in urls:
                self._append_job(url)
            self.url.clear()
            self.info.setText(f"{len(urls)} item(ns) adicionado(s) à fila.")
        except Exception as exc:
            QMessageBox.warning(self, "Fila", str(exc))

    def download_now(self):
        self.add_to_queue()
        self.start_queue()

    def start_queue(self):
        if self._thread and self._thread.isRunning():
            return
        for index, job in enumerate(self.jobs):
            if self.items[index].text().startswith(("⏳", "🔄")):
                self._start_job(index)
                return
        self.info.setText("Fila vazia ou todos os itens já concluídos.")

    def _start_job(self, index: int):
        self.active_index = index
        item = self.items[index]
        item.setText("🔄 " + item.text()[2:])
        self.progress.setValue(0)
        self.info.setText(f"Baixando {index + 1}/{len(self.jobs)}…")
        self._thread = QThread(self)
        self._worker = DownloadWorker(self.jobs[index], self.output_dir)
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
            self._thread.wait(3000)
        self._worker = None
        self._thread = None

    def on_progress(self, data):
        total = data.get("total_bytes") or data.get("total_bytes_estimate")
        done = data.get("downloaded_bytes", 0)
        if total:
            self.progress.setValue(max(0, min(100, int(done * 100 / total))))
        speed = data.get("speed")
        eta = data.get("eta")
        if speed:
            mbps = speed / 1024 / 1024
            self.info.setText(f"Baixando • {mbps:.1f} MiB/s" + (f" • ETA {eta}s" if eta else ""))

    def _next_or_finish(self):
        self._cleanup_thread()
        next_index = next((i for i, item in enumerate(self.items) if item.text().startswith("⏳")), None)
        if next_index is not None:
            self._start_job(next_index)
        else:
            self.info.setText(f"Fila concluída • {self.output_dir}")

    def on_finished(self):
        if self.active_index >= 0:
            item = self.items[self.active_index]
            item.setText("✅ " + item.text()[2:] + " • concluído")
            self.progress.setValue(100)
            self._save_history(self.jobs[self.active_index].url, "concluído")
        self._next_or_finish()

    def on_cancelled(self):
        if self.active_index >= 0:
            self.items[self.active_index].setText("⏹ " + self.items[self.active_index].text()[2:] + " • cancelado")
            self._save_history(self.jobs[self.active_index].url, "cancelado")
        self._next_or_finish()

    def on_failed(self, message):
        if self.active_index >= 0:
            self.items[self.active_index].setText("❌ " + self.items[self.active_index].text()[2:] + " • falhou")
            self._save_history(self.jobs[self.active_index].url, "falhou: " + message[:120])
        QMessageBox.warning(self, "Download", message)
        self._next_or_finish()

    def cancel_current(self):
        if self._worker:
            self.info.setText("Cancelando…")
            self._worker.cancel()

    def clear_completed(self):
        for i in reversed(range(len(self.items))):
            if self.items[i].text().startswith(("✅", "❌", "⏹")):
                item = self.items.pop(i)
                self.jobs.pop(i)
                self.queue.takeItem(self.queue.row(item))
        for i, item in enumerate(self.items):
            item.setData(Qt.UserRole, i)
        self.info.setText("Concluídos removidos da tela. Histórico preservado.")

    @property
    def history_file(self) -> Path:
        return self.output_dir / ".marqueslab-history.json"

    def _load_history(self):
        try:
            data = json.loads(self.history_file.read_text(encoding="utf-8"))
            lines = [f"{x['date']} • {x['status']} • {x['url']}" for x in data[-20:]]
            self.history.setPlainText("\n".join(reversed(lines)))
        except Exception:
            self.history.clear()

    def _save_history(self, url: str, status: str):
        try:
            data = []
            if self.history_file.exists():
                data = json.loads(self.history_file.read_text(encoding="utf-8"))
            data.append({"date": datetime.now().strftime("%Y-%m-%d %H:%M"), "url": url, "status": status})
            self.output_dir.mkdir(parents=True, exist_ok=True)
            self.history_file.write_text(json.dumps(data[-100:], ensure_ascii=False, indent=2), encoding="utf-8")
            self._load_history()
        except Exception:
            pass

    def closeEvent(self, event):
        if self._worker:
            self._worker.cancel()
        self._cleanup_thread()
        event.accept()


if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setApplicationName("Marques Lab 4K Download")
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
