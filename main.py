"""ArcaeaNap 앱 엔트리포인트."""
import sys
import os



from PyQt6.QtGui import QGuiApplication, QSurfaceFormat
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtCore import QUrl

from utils.app_fonts import register_embedded_fonts, get_app_root
from handlers.startup_handler import StartupHandler
from handlers.analysis_handler import AnalysisHandler
from handlers.stats_handler import StatsHandler
from handlers.statistics_handler import StatisticsHandler
from handlers.profile_handler import ProfileHandler
from handlers.settings_handler import SettingsHandler


def main():
    fmt = QSurfaceFormat()
    fmt.setSamples(8)  # MSAA 8x
    fmt.setRenderableType(QSurfaceFormat.RenderableType.OpenGL)
    QSurfaceFormat.setDefaultFormat(fmt)

    app = QGuiApplication(sys.argv)
    qml_font_context = register_embedded_fonts()

    print("Arcaea Nap v0.1")

    print("UI loading...")
    engine = QQmlApplicationEngine()
    for key, value in qml_font_context.items():
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

    # Refresh profile when Arcaea Online connection changes
    settings_handler.arcaeaOnlineConnectionChanged.connect(profile_handler.refreshProfile)

    qml_filename = "main.qml"
    qml_filepath = os.path.join(get_app_root(), 'ui', qml_filename)

    engine.load(QUrl.fromLocalFile(qml_filepath))

    if not engine.rootObjects():
        sys.exit(-1)

    # Stop browser on app exit
    app.aboutToQuit.connect(analysis_handler.stopAnalysis)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
