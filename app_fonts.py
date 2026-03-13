"""Application font registration and QML context mapping utilities."""

from __future__ import annotations

import os

from PyQt6.QtGui import QFontDatabase

BASE_UI_FONT_FAMILY = "Segoe UI, Roboto, Helvetica, Arial, sans-serif"
TITLE_FONT_DIRNAME = "Fonts"
TITLE_FONT_FILENAME = "NotoSansJP-VariableFont_wght.ttf"

CONTEXT_KEY_BASE_UI_FONT = "embeddedBaseUiFontFamily"
CONTEXT_KEY_TITLE_FONT = "embeddedTitleFontFamily"

def _make_qml_context(base_ui_font_family: str, title_font_family: str) -> dict[str, str]:
    return {
        CONTEXT_KEY_BASE_UI_FONT: base_ui_font_family,
        CONTEXT_KEY_TITLE_FONT: title_font_family,
    }

def register_embedded_fonts(cache_path: str) -> dict[str, str]:
    """Register embedded title font and return QML context properties."""
    base_ui_font_family = BASE_UI_FONT_FAMILY
    title_font_family = base_ui_font_family

    font_path = os.path.join(cache_path, TITLE_FONT_DIRNAME, TITLE_FONT_FILENAME)
    if not os.path.exists(font_path):
        print(f"[font] Missing title font file: {font_path}")
        print("[font] Title font load skipped; fallback to base UI font")
        
        return _make_qml_context(base_ui_font_family, title_font_family)

    font_id = QFontDatabase.addApplicationFont(font_path)
    if font_id == -1:
        print(f"[font] Failed to load title font: {font_path}")
        print("[font] Title font load skipped; fallback to base UI font")
        
        return _make_qml_context(base_ui_font_family, title_font_family)

    families = QFontDatabase.applicationFontFamilies(font_id)
    if not families:
        print(f"[font] Loaded title font file but no family detected: {font_path}")
        print("[font] Title font load skipped; fallback to base UI font")
        
        return _make_qml_context(base_ui_font_family, title_font_family)

    title_font_family = families[0]
    print(f"[font] Loaded title font '{title_font_family}' from {font_path}")
    
    return _make_qml_context(base_ui_font_family, title_font_family)
