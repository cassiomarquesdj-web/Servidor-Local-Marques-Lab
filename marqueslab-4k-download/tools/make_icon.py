"""Generate the macOS application icon (assets/AppIcon.icns).

Run locally after changing the artwork:

    python tools/make_icon.py

The generated .iconset and .icns are committed so CI builds do not depend on a
GUI toolkit being able to render offscreen.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QPointF, QRectF, Qt  # noqa: E402
from PySide6.QtGui import (  # noqa: E402
    QBrush, QColor, QFont, QGuiApplication, QImage, QLinearGradient, QPainter,
    QPainterPath, QPen,
)

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
ICONSET = ASSETS / "AppIcon.iconset"
ICNS = ASSETS / "AppIcon.icns"

# macOS icon grid: artwork occupies ~82% of the canvas, centred.
MARGIN_RATIO = 0.09
CORNER_RATIO = 0.225


def render(size: int) -> QImage:
    image = QImage(size, size, QImage.Format_ARGB32_Premultiplied)
    image.fill(Qt.transparent)
    painter = QPainter(image)
    painter.setRenderHints(QPainter.Antialiasing | QPainter.SmoothPixmapTransform | QPainter.TextAntialiasing)

    margin = size * MARGIN_RATIO
    body = QRectF(margin, margin, size - 2 * margin, size - 2 * margin)
    radius = body.width() * CORNER_RATIO

    shell = QPainterPath()
    shell.addRoundedRect(body, radius, radius)

    backdrop = QLinearGradient(body.topLeft(), body.bottomRight())
    backdrop.setColorAt(0.0, QColor("#1b2030"))
    backdrop.setColorAt(0.55, QColor("#11141b"))
    backdrop.setColorAt(1.0, QColor("#080a0e"))
    painter.fillPath(shell, QBrush(backdrop))

    gloss = QLinearGradient(body.topLeft(), QPointF(body.left(), body.center().y()))
    gloss.setColorAt(0.0, QColor(255, 255, 255, 34))
    gloss.setColorAt(1.0, QColor(255, 255, 255, 0))
    painter.fillPath(shell, QBrush(gloss))

    painter.setPen(QPen(QColor(255, 255, 255, 46), max(1.0, size * 0.006)))
    painter.drawPath(shell)

    # Download arrow
    painter.save()
    painter.setClipPath(shell)
    accent = QLinearGradient(QPointF(body.center().x(), body.top()), QPointF(body.center().x(), body.bottom()))
    accent.setColorAt(0.0, QColor("#5aa2ff"))
    accent.setColorAt(1.0, QColor("#1d5fd0"))

    cx = body.center().x()
    stem_w = body.width() * 0.135
    stem_top = body.top() + body.height() * 0.17
    stem_bottom = body.top() + body.height() * 0.47
    stem = QPainterPath()
    stem.addRoundedRect(
        QRectF(cx - stem_w / 2, stem_top, stem_w, stem_bottom - stem_top),
        stem_w * 0.35,
        stem_w * 0.35,
    )
    painter.fillPath(stem, QBrush(accent))

    head_w = body.width() * 0.40
    head = QPainterPath()
    head.moveTo(cx - head_w / 2, stem_bottom - stem_w * 0.15)
    head.lineTo(cx + head_w / 2, stem_bottom - stem_w * 0.15)
    head.lineTo(cx, body.top() + body.height() * 0.665)
    head.closeSubpath()
    painter.fillPath(head, QBrush(accent))

    # Base tray
    tray_w = body.width() * 0.52
    tray_h = body.height() * 0.055
    tray = QPainterPath()
    tray.addRoundedRect(
        QRectF(cx - tray_w / 2, body.top() + body.height() * 0.735, tray_w, tray_h),
        tray_h / 2,
        tray_h / 2,
    )
    painter.fillPath(tray, QBrush(QColor("#8fb7f5")))

    # "4K" wordmark
    font = QFont()
    font.setFamilies(["SF Pro Display", "Helvetica Neue", "Arial"])
    font.setPixelSize(int(body.height() * 0.155))
    font.setWeight(QFont.Black)
    font.setLetterSpacing(QFont.PercentageSpacing, 104)
    painter.setFont(font)
    painter.setPen(QColor("#f4f5f7"))
    label = QRectF(body.left(), body.top() + body.height() * 0.80, body.width(), body.height() * 0.16)
    painter.drawText(label, Qt.AlignHCenter | Qt.AlignVCenter, "4K")
    painter.restore()

    painter.end()
    return image


def build() -> Path:
    if sys.platform != "darwin":
        raise SystemExit("iconutil is only available on macOS")
    QGuiApplication.instance() or QGuiApplication([])
    ASSETS.mkdir(parents=True, exist_ok=True)
    if ICONSET.exists():
        for stale in ICONSET.glob("*.png"):
            stale.unlink()
    ICONSET.mkdir(parents=True, exist_ok=True)

    for base in (16, 32, 128, 256, 512):
        render(base).save(str(ICONSET / f"icon_{base}x{base}.png"), "PNG")
        render(base * 2).save(str(ICONSET / f"icon_{base}x{base}@2x.png"), "PNG")

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    return ICNS


if __name__ == "__main__":
    path = build()
    print(f"ICON: {path} ({path.stat().st_size} bytes)")
