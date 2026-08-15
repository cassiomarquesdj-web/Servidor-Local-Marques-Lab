from __future__ import annotations

import sys
from pathlib import Path
from PySide6.QtCore import QObject, QThread, Signal, Slot
from PySide6.QtWidgets import (
    QApplication, QFileDialog, QComboBox, QHBoxLayout, QLabel, QLineEdit,
    QListWidget, QListWidgetItem, QMainWindow, QMessageBox, QProgressBar,
    QPushButton, QVBoxLayout, QWidget
)

from engine import DownloadEngine, choose_audio, choose_video, normalize_url


class JobWorker(QObject):
    progress = Signal(dict)
    finished = Signal()
    failed = Signal(str)

    def __init__(self, url: str, output: Path, choice):
        super().__init__()
        self.url, self.output, self.choice = url, output, choice

    @Slot()
    def run(self):
        try:
            engine = DownloadEngine(self.output, self.progress.emit)
            engine.download(self.url, self.choice)
            self.finished.emit()
        except Exception as exc:
            self.failed.emit(str(exc))


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Marques Lab 4K Download")
        self.resize(980, 680)
        self.output_dir = Path.home() / "Downloads" / "Marques Lab 4K Download"
        self._build()

    def _build(self):
        root = QWidget()
        layout = QVBoxLayout(root)
        title = QLabel("MARQUES LAB 4K DOWNLOAD")
        title.setObjectName("title")
        subtitle = QLabel("Force Download • MP3 • MP4 • até 4K quando disponível")
        layout.addWidget(title)
        layout.addWidget(subtitle)

        row = QHBoxLayout()
        self.url = QLineEdit()
        self.url.setPlaceholderText("Cole a URL da mídia autorizada para download…")
        row.addWidget(self.url, 1)
        self.analyze_btn = QPushButton("ANALISAR")
        self.force_btn = QPushButton("FORCE DOWNLOAD")
        row.addWidget(self.analyze_btn)
        row.addWidget(self.force_btn)
        layout.addLayout(row)

        opts = QHBoxLayout()
        self.mode = QComboBox()
        self.mode.addItems(["MP4 • Vídeo", "MP3 • Áudio"])
        self.quality = QComboBox()
        self.quality.addItems(["Melhor disponível", "2160p • 4K", "1440p", "1080p"])
        self.folder_btn = QPushButton("PASTA DE SAÍDA")
        opts.addWidget(QLabel("Formato:"))
        opts.addWidget(self.mode)
        opts.addWidget(QLabel("Qualidade:"))
        opts.addWidget(self.quality)
        opts.addWidget(self.folder_btn)
        layout.addLayout(opts)

        self.info = QLabel("Pronto. O Force Download usa a melhor fonte permitida e disponível.")
        layout.addWidget(self.info)
        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        layout.addWidget(self.progress)
        self.queue = QListWidget()
        layout.addWidget(self.queue, 1)

        self.setCentralWidget(root)
        self.setStyleSheet("""
            QWidget { background:#101114; color:#f3f3f3; font-size:14px; }
            QLineEdit, QComboBox, QListWidget { background:#181a1f; border:1px solid #30333a; padding:10px; }
            QPushButton { background:#252830; border:1px solid #444955; padding:10px 16px; font-weight:700; }
            QPushButton:hover { background:#30343d; }
            #title { font-size:26px; font-weight:900; padding-top:8px; }
        """)
        self.analyze_btn.clicked.connect(self.analyze)
        self.force_btn.clicked.connect(self.force_download)
        self.folder_btn.clicked.connect(self.choose_folder)

    def choose_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Escolha a pasta de saída", str(self.output_dir))
        if folder:
            self.output_dir = Path(folder)
            self.info.setText(f"Saída: {self.output_dir}")

    def analyze(self):
        try:
            url = normalize_url(self.url.text())
            self.info.setText("Analisando fonte…")
            engine = DownloadEngine(self.output_dir)
            info = engine.analyze(url)
            title = info.get("title", "Mídia")
            duration = info.get("duration")
            formats = info.get("formats") or []
            heights = sorted({f.get("height") for f in formats if f.get("height")}, reverse=True)
            quality = f"até {heights[0]}p" if heights else "qualidade não informada"
            self.info.setText(f"{title} • {quality}" + (f" • {duration}s" if duration else ""))
        except Exception as exc:
            QMessageBox.critical(self, "Falha na análise", str(exc))

    def force_download(self):
        try:
            url = normalize_url(self.url.text())
        except Exception as exc:
            QMessageBox.warning(self, "URL", str(exc))
            return
        if self.mode.currentIndex() == 1:
            choice = choose_audio()
        else:
            labels = {0: "best", 1: "2160p", 2: "1440p", 3: "1080p"}
            choice = choose_video(labels[self.quality.currentIndex()])
        item = QListWidgetItem(f"⏳ {choice.mode.upper()} • {url}")
        self.queue.addItem(item)
        self.force_btn.setEnabled(False)
        self._thread = QThread(self)
        self._worker = JobWorker(url, self.output_dir, choice)
        self._worker.moveToThread(self._thread)
        self._thread.started.connect(self._worker.run)
        self._worker.progress.connect(self.on_progress)
        self._worker.finished.connect(lambda: self.on_finished(item))
        self._worker.failed.connect(lambda msg: self.on_failed(item, msg))
        self._worker.finished.connect(self._thread.quit)
        self._worker.failed.connect(lambda _: self._thread.quit())
        self._thread.finished.connect(lambda: self.force_btn.setEnabled(True))
        self._thread.start()

    def on_progress(self, data):
        total = data.get("total_bytes") or data.get("total_bytes_estimate")
        done = data.get("downloaded_bytes", 0)
        if total:
            self.progress.setValue(int(done * 100 / total))

    def on_finished(self, item):
        self.progress.setValue(100)
        item.setText("✅ " + item.text()[2:] + " • concluído")
        self.info.setText(f"Concluído: {self.output_dir}")

    def on_failed(self, item, message):
        item.setText("❌ " + item.text()[2:] + " • falhou")
        self.info.setText("Falha no download")
        QMessageBox.warning(self, "Download", message)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())
