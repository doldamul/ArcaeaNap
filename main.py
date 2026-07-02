"""ArcaeaNap 앱 엔트리포인트."""
import sys
import os

from PyQt6.QtGui import QGuiApplication, QSurfaceFormat, QIcon, QImageReader, QPixmap
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtCore import QUrl, QByteArray, QBuffer, QIODevice, Qt, QTimer

from utils.app_fonts import register_embedded_fonts, get_app_root
from handlers.startup_handler import StartupHandler
from handlers.analysis_handler import AnalysisHandler
from handlers.stats_handler import StatsHandler
from handlers.statistics_handler import StatisticsHandler
from handlers.profile_handler import ProfileHandler
from handlers.settings_handler import SettingsHandler
from handlers.update_handler import UpdateHandler
from services.about_service import build_about_context
try:
    from utils.embedded_app_icon import get_embedded_app_icon
except Exception:
    def get_embedded_app_icon() -> QIcon:
        return QIcon()


def _icon_to_data_url(icon: QIcon, size: int = 64) -> str:
    if icon.isNull():
        return ""
    pixmap = icon.pixmap(size, size)
    if pixmap.isNull():
        return ""
    data = QByteArray()
    buffer = QBuffer(data)
    if not buffer.open(QIODevice.OpenModeFlag.WriteOnly):
        return ""
    pixmap.save(buffer, "PNG")
    buffer.close()
    return "data:image/png;base64," + bytes(data.toBase64()).decode("ascii")


def _build_multi_size_icon_from_embedded() -> QIcon:
    try:
        from utils import embedded_app_icon as embedded_icon_module
    except Exception:
        return QIcon()

    raw_b64 = getattr(embedded_icon_module, "_ICON_B64", "")
    if not raw_b64:
        return QIcon()

    binary = QByteArray.fromBase64(raw_b64.encode("ascii"))
    buffer = QBuffer(binary)
    if not buffer.open(QIODevice.OpenModeFlag.ReadOnly):
        return QIcon()

    reader = QImageReader(buffer, b"ico")
    if not reader.canRead():
        buffer.close()
        return QIcon()

    icon = QIcon()
    while True:
        image = reader.read()
        if image.isNull():
            break
        pixmap = QPixmap.fromImage(image)
        if not pixmap.isNull():
            icon.addPixmap(pixmap)
        if not reader.jumpToNextImage():
            break

    buffer.close()
    return icon


def _resolve_icons():
    icon = _build_multi_size_icon_from_embedded()
    if icon.isNull():
        icon = get_embedded_app_icon()
    if not icon.isNull():
        return icon, _icon_to_data_url(icon, size=256)

    fallback_ico = os.path.join(get_app_root(), "resources", "logo.ico")
    if os.path.isfile(fallback_ico):
        file_icon = QIcon(fallback_ico)
        return file_icon, _icon_to_data_url(file_icon, size=256)

    return QIcon(), ""


def _set_windows_app_user_model_id():
    if os.name != "nt":
        return
    try:
        import ctypes
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("ArcaeaNap.Desktop.App")
    except Exception as e:
        print(f"[main] Failed to set AppUserModelID: {e}")


def main():
    _set_windows_app_user_model_id()

    fmt = QSurfaceFormat()
    fmt.setSamples(8)  # MSAA 8x
    fmt.setRenderableType(QSurfaceFormat.RenderableType.OpenGL)
    QSurfaceFormat.setDefaultFormat(fmt)

    app = QGuiApplication(sys.argv)
    # Temporary patch: the UI is light-only, but QtQuick.Controls.Basic controls
    # without an explicit text color (radio buttons, toggles, the About "Open
    # Source Licenses" button) fall back to the palette's dark-mode text color and
    # become invisible under macOS Dark Mode. Force the Light color scheme until a
    # proper dark theme is implemented.
    app.styleHints().setColorScheme(Qt.ColorScheme.Light)
    qml_font_context = register_embedded_fonts()
    app_icon, app_logo_source = _resolve_icons()
    about_context = build_about_context(get_app_root())

    # On macOS the Dock/app icon comes from the app bundle (Assets.car / .icns).
    # Calling setWindowIcon here would override that bundle icon at runtime with the
    # embedded legacy icon, so only set it programmatically off-macOS (Windows/Linux
    # taskbar need it).
    if sys.platform != "darwin":
        if not app_icon.isNull():
            app.setWindowIcon(app_icon)
        else:
            print("[main] App icon file not found; using default executable icon.")

    print(f"Arcaea Nap v{about_context['appVersion']}")

    print("UI loading...")
    engine = QQmlApplicationEngine()
    for key, value in qml_font_context.items():
        engine.rootContext().setContextProperty(key, value)
    engine.rootContext().setContextProperty(
        "appLogoSource",
        app_logo_source,
    )
    for key, value in about_context.items():
        engine.rootContext().setContextProperty(key, value)

    # Register handlers
    analysis_handler = AnalysisHandler()
    engine.rootContext().setContextProperty("analysisHandler", analysis_handler)

    startup_handler = StartupHandler()
    engine.rootContext().setContextProperty("startupHandler", startup_handler)

    stats_handler = StatsHandler()
    engine.rootContext().setContextProperty("statsHandler", stats_handler)

    statistics_handler = StatisticsHandler()
    engine.rootContext().setContextProperty("statisticsHandler", statistics_handler)

    profile_handler = ProfileHandler()
    engine.rootContext().setContextProperty("profileHandler", profile_handler)

    settings_handler = SettingsHandler()
    settings_handler.set_analyzer(analysis_handler.analyzer)
    analysis_handler.set_settings_handler(settings_handler)  # Enable connection status updates
    engine.rootContext().setContextProperty("settingsHandler", settings_handler)

    update_handler = UpdateHandler()
    engine.rootContext().setContextProperty("updateHandler", update_handler)

    # Refresh profile when Arcaea Online connection changes
    settings_handler.arcaeaOnlineConnectionChanged.connect(profile_handler.refreshProfile)

    qml_filename = "main.qml"
    if getattr(sys, "frozen", False):
        qml_filepath = os.path.join(get_app_root(), "resources", "ui", qml_filename)
    else:
        qml_filepath = os.path.join(get_app_root(), "ui", qml_filename)

    engine.load(QUrl.fromLocalFile(qml_filepath))

    if not engine.rootObjects():
        sys.exit(-1)

    root_window = engine.rootObjects()[0]
    if sys.platform != "darwin" and hasattr(root_window, "setIcon"):
        if not app_icon.isNull():
            root_window.setIcon(app_icon)

    # Stop browser on app exit
    app.aboutToQuit.connect(analysis_handler.stopAnalysis)

    # 시작 후 3초 뒤 백그라운드 업데이트 체크(실패 시 조용히 무시).
    QTimer.singleShot(3000, update_handler.check_on_startup)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
