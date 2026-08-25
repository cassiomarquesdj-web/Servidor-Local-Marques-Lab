"""Single source of truth for product identity.

Imported by the application, the PyInstaller spec, the icon generator and the
macOS packaging scripts so that the name, version and bundle identifier can
never drift between the app, the .app bundle, the DMG and the GitHub release.
"""
from __future__ import annotations

APP_NAME = "Marques Lab 4K Download"
APP_SLUG = "MarquesLab-4K-Download"
BUNDLE_ID = "com.marqueslab.MarquesLab4KDownload"
VERSION = "1.0.0"
COPYRIGHT = "© Marques Lab"
ORGANIZATION = "Marques Lab"
MINIMUM_MACOS = "12.0"  # deployment target real das bibliotecas Qt embarcadas

__all__ = [
    "APP_NAME",
    "APP_SLUG",
    "BUNDLE_ID",
    "VERSION",
    "COPYRIGHT",
    "ORGANIZATION",
    "MINIMUM_MACOS",
]
