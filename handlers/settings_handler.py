"""Settings 탭 핸들러: 설정 관리, 계정 연동, 시트 관리, Song DB 업데이트, 프로필."""
from utils.configuration import config
import os
import threading
import time
from datetime import datetime
from PyQt6.QtCore import QObject, pyqtSlot, pyqtSignal, QVariant
from utils.web_arcaeaonline import ArcaeaOnline
from utils.song_db_builder import rebuild_songs_db
from services.connection_store import (
    STORE_FILENAME as CONNECTION_STORE_FILENAME,
    load_client_connections,
    save_client_connections,
)
from services.keyring_store import delete_secret
from services.write_conflict_guard import (
    detect_recent_external_activity,
)


class SettingsHandler(QObject):
    settingsChanged = pyqtSignal()
    profileDisplayChanged = pyqtSignal()  # Profile image, show friend code, show potential
    mostPlayedOrderChanged = pyqtSignal()  # Grouping criteria, difficulty filter, most played scope
    songTitleLanguageChanged = pyqtSignal()
    cachePathChanged = pyqtSignal()
    cachePathApplied = pyqtSignal()
    analyzeModeChanged = pyqtSignal(bool, arguments=['enabled'])
    # Migration signals
    cacheMigrationStarting = pyqtSignal()  # Emitted before migration - QML should release file handles
    cacheMigrationFinished = pyqtSignal(str, arguments=['error'])  # Emitted after migration with error message (empty if success)
    # Account connection signals
    arcaeaOnlineConnectionChanged = pyqtSignal()
    googleSheetConnectionChanged = pyqtSignal()
    # Sheet binding signals
    sheetBindingChanged = pyqtSignal()
    sendDataStatusChanged = pyqtSignal()
    sheetVersionsChanged = pyqtSignal()
    # Song database update signals
    songDatabaseUpdateStarting = pyqtSignal()
    songDatabaseUpdateFinished = pyqtSignal(bool, str, arguments=['success', 'message'])
    songDatabaseWriteConflictDetected = pyqtSignal(str, arguments=['message'])
    
    # Browser setup signals
    browserInstallStatusChanged = pyqtSignal()
    browserInstallLogAdded = pyqtSignal(str, arguments=['message'])

    def __init__(self):
        super().__init__()
        self._pending_migration_path = None  # Stores the new path during migration
        self._analyzer = None
        self._is_arcaea_connecting = False
        self._is_binding_sheet = False
        self._is_sending_data = False
        self._is_updating_song_db = False
        self._google_cancellation_context = None
        self._bind_cancellation_context = None
        self._send_cancellation_context = None
        self._arcaea_login_instance = None
        self._sheet_versions = self._load_sheet_versions()
        self._is_installing_browser = False
        self._browser_installed = None

    def set_analyzer(self, analyzer):
        """Connect to ArcaeaOnline instance for play count mode control."""
        self._analyzer = analyzer

    # --- General Settings ---
    @pyqtSlot(result=str)
    def getCachePath(self):
        return config['general']['cache_path']

    @pyqtSlot(result=str)
    def getSongTitleLanguage(self):
        return config['general']['song_title_language']

    @pyqtSlot(str)
    def setSongTitleLanguage(self, lang):
        normalized = str(lang or '').strip().lower()
        if normalized not in ('en', 'jp'):
            return
        if normalized == config['general']['song_title_language']:
            return
        config['general']['song_title_language'] = normalized
        self.songTitleLanguageChanged.emit()
        self.settingsChanged.emit()

    def _get_absolute_cache_path(self, path: str) -> str:
        """Convert cache path to absolute path, resolving relative paths from script directory."""
        if path.startswith('./') or path.startswith('.\\'):
            base_dir = os.path.dirname(os.path.abspath(__file__))
            project_root = os.path.dirname(base_dir)
            return os.path.normpath(os.path.join(project_root, path))
        return os.path.abspath(path)

    def _emit_cache_path_applied_updates(self):
        """Emit all state-refresh signals after cache path is successfully applied."""
        self._sheet_versions = self._load_sheet_versions()
        self.cachePathChanged.emit()
        self.settingsChanged.emit()
        self.arcaeaOnlineConnectionChanged.emit()
        self.googleSheetConnectionChanged.emit()
        self.sheetBindingChanged.emit()
        self.sheetVersionsChanged.emit()
        self.cachePathApplied.emit()

    @pyqtSlot(str)
    def prepareCacheMigration(self, new_path):
        """
        Step 1 of cache migration: Store target path and signal QML to release file handles.
        After this, QML should show loading modal and release all file handles,
        then call executeCacheMigration().
        """
        # Allow use of file:// prefix for drag-and-drop support or dialog returns
        if new_path.startswith("file:///"):
            new_path = new_path[8:]
        
        old_path = config['general']['cache_path']
        old_abs = self._get_absolute_cache_path(old_path)
        new_abs = os.path.abspath(new_path)
        
        # Same path check
        if os.path.normpath(old_abs) == os.path.normpath(new_abs):
            return
        
        self._pending_migration_path = new_path
        print(f"[SettingsHandler] Preparing cache migration to '{new_path}'...")
        self.cacheMigrationStarting.emit()

    @pyqtSlot(str)
    def switchCachePathOnly(self, new_path):
        """
        Switch cache_path without migrating data files.
        This mode is intended for multi-client usage where existing files are kept as-is.
        """
        if new_path.startswith("file:///"):
            new_path = new_path[8:]

        old_path = config['general']['cache_path']
        old_abs = self._get_absolute_cache_path(old_path)
        new_abs = os.path.abspath(new_path)

        if os.path.normpath(old_abs) == os.path.normpath(new_abs):
            return

        os.makedirs(new_abs, exist_ok=True)
        config['general']['cache_path'] = new_path
        print(f"[SettingsHandler] Cache path switched without migration: '{old_abs}' -> '{new_abs}'")
        self._emit_cache_path_applied_updates()

    @pyqtSlot()
    def executeCacheMigration(self):
        """
        Step 2 of cache migration: Actually copy files and update config.
        Should be called by QML after it has released all file handles.
        """
        import shutil
        
        if not self._pending_migration_path:
            self.cacheMigrationFinished.emit("No pending migration")
            return
        
        new_path = self._pending_migration_path
        self._pending_migration_path = None
        
        old_path = config['general']['cache_path']
        old_abs = self._get_absolute_cache_path(old_path)
        new_abs = os.path.abspath(new_path)
        
        # Data files/folders to migrate
        data_items = [
            'thumbnails',
            'user_scores.db',
            'login.dat',
            'songs.db',
            CONNECTION_STORE_FILENAME,
            'client_secret.json',
        ]
        
        copied_items = []
        try:
            # Ensure new directory exists
            os.makedirs(new_abs, exist_ok=True)
            
            # Phase 1: Copy all items to new location
            for item in data_items:
                src = os.path.join(old_abs, item)
                dst = os.path.join(new_abs, item)
                
                if not os.path.exists(src):
                    continue
                
                if os.path.isdir(src):
                    if os.path.exists(dst):
                        shutil.rmtree(dst)
                    shutil.copytree(src, dst)
                else:
                    shutil.copy2(src, dst)
                
                copied_items.append(item)
            
            # Phase 2: Verify copied items exist
            for item in copied_items:
                dst = os.path.join(new_abs, item)
                if not os.path.exists(dst):
                    raise IOError(f"Verification failed: {item} not found in new location")
            
            # Phase 3: Update config (this is the point of no return)
            config['general']['cache_path'] = new_path
            self._emit_cache_path_applied_updates()
            
            # Phase 4: Delete old items (failure here is acceptable - data is safe in new location)
            for item in copied_items:
                src = os.path.join(old_abs, item)
                try:
                    if os.path.isdir(src):
                        shutil.rmtree(src, ignore_errors=True)
                    else:
                        os.remove(src)
                except Exception as e:
                    print(f"[SettingsHandler] Warning: Could not delete old {item}: {e}")
            
            print(f"[SettingsHandler] Cache moved from '{old_abs}' to '{new_abs}'")
            self.cacheMigrationFinished.emit("")  # Success
            
        except Exception as e:
            # Rollback: remove any partially copied items from new location
            print(f"[SettingsHandler] Copy failed, attempting rollback...")
            for item in copied_items:
                dst = os.path.join(new_abs, item)
                try:
                    if os.path.isdir(dst):
                        shutil.rmtree(dst, ignore_errors=True)
                    elif os.path.exists(dst):
                        os.remove(dst)
                except Exception:
                    pass
            
            error_msg = f"Failed to move cache: {e}"
            print(f"[SettingsHandler] {error_msg}")
            self.cacheMigrationFinished.emit(error_msg)

    @pyqtSlot()
    def cancelCacheMigration(self):
        """Cancel a pending migration."""
        self._pending_migration_path = None
        self.cacheMigrationFinished.emit("Migration cancelled")

    @pyqtSlot()
    def openCacheFolder(self):
        """Open the cache folder in the system file explorer."""
        import subprocess
        cache_path = self._get_absolute_cache_path(config['general']['cache_path'])
        
        if os.path.isdir(cache_path):
            # Windows
            subprocess.Popen(['explorer', cache_path])

    @pyqtSlot(result=bool)
    def getAnalyzeModeEnabled(self):
        return config['general']['analyze_mode']

    @pyqtSlot(bool)
    def setAnalyzeModeEnabled(self, enabled):
        if self._analyzer:
            self._analyzer.set_play_count_mode(enabled)
        else:
            config['general']['analyze_mode'] = enabled
        self.analyzeModeChanged.emit(enabled)
        self.settingsChanged.emit()
        
    @pyqtSlot(result=bool)
    def isUpdatingSongDatabase(self):
        return self._is_updating_song_db

    @pyqtSlot()
    def updateSongDatabase(self):
        self._start_song_database_update(force=False)

    @pyqtSlot()
    def forceUpdateSongDatabase(self):
        self._start_song_database_update(force=True)

    def _start_song_database_update(self, force: bool):
        if self._is_updating_song_db:
            return

        if not force:
            conflict = detect_recent_external_activity("songs_db")
            if conflict:
                message = (
                    "Recent write activity to songs.db was detected from another client.\n"
                    f"- host: {conflict.hostname}\n"
                    f"- operation: {conflict.operation or 'unknown'}\n"
                    "Force Update may cause data conflicts."
                )
                self.songDatabaseWriteConflictDetected.emit(message)
                return

        self._is_updating_song_db = True
        self.songDatabaseUpdateStarting.emit()

        def worker():
            import traceback
            try:
                rebuild_songs_db()
                self.songDatabaseUpdateFinished.emit(True, "Song database updated successfully.")
            except Exception as e:
                print(f"[SettingsHandler] Song database update failed: {e}")
                traceback.print_exc()
                self.songDatabaseUpdateFinished.emit(False, str(e))
            finally:
                self._is_updating_song_db = False

        threading.Thread(target=worker, daemon=True).start()

    # --- Sheet Management ---
    @pyqtSlot(result='QVariant')
    def getBoundSheetInfo(self):
        """Get bound sheet info as dict."""
        connections = self._load_connections()
        gs_info = connections.get('google_sheet', {})
        bound_id = gs_info.get('bound_sheet_id', '')
        bound_name = gs_info.get('bound_sheet_name', '')
        if not bound_id:
            return {}
        return {
            'sheet_id': bound_id,
            'sheet_name': bound_name
        }

    def _load_sheet_versions(self):
        """Load sheet versions from account_connections.json."""
        connections = self._load_connections()
        gs_info = connections.get('google_sheet', {})
        sheet_ver = gs_info.get('sheet_ver', '')
        arcaea_ver = gs_info.get('arcaea_ver', '')
        if sheet_ver or arcaea_ver:
            return {'sheet_ver': sheet_ver, 'arcaea_ver': arcaea_ver}
        return {'sheet_ver': '?', 'arcaea_ver': '?'}

    def _fetch_and_save_sheet_versions(self):
        """Fetch sheet version info from API and save to account_connections.json."""
        self._sheet_versions = {'sheet_ver': '?', 'arcaea_ver': '?'}
        self.sheetVersionsChanged.emit()

        print("[SettingsHandler] Fetching sheet versions...")
        from utils.web_consultantsheet import get_sheet_version_info
        versions = get_sheet_version_info()
        print(f"[SettingsHandler] Sheet versions fetched: {versions}")

        # If credentials were expired/revoked, notify UI.
        if versions.get('disconnected'):
            print("[SettingsHandler] Google Sheet connection was lost (token expired/revoked).")
            self._sheet_versions = {'sheet_ver': '', 'arcaea_ver': ''}
            self.sheetVersionsChanged.emit()
            self.googleSheetConnectionChanged.emit()
            return

        # Save to account_connections.json
        sheet_ver = versions.get('sheet_ver', '?')
        arcaea_ver = versions.get('arcaea_ver', '?')
        connections = self._load_connections()
        gs_info = connections.get('google_sheet', {})
        gs_info['sheet_ver'] = sheet_ver if sheet_ver != '?' else ''
        gs_info['arcaea_ver'] = arcaea_ver if arcaea_ver != '?' else ''
        connections['google_sheet'] = gs_info
        self._save_connections(connections)

        self._sheet_versions = {'sheet_ver': sheet_ver, 'arcaea_ver': arcaea_ver}
        self.sheetVersionsChanged.emit()

    @pyqtSlot(result='QVariant')
    def getSheetVersions(self):
        """Get sheet versions (from in-memory cache, loaded from account_connections.json)."""
        return self._sheet_versions


    @pyqtSlot(result=bool)
    def isBindingSheet(self):
        return self._is_binding_sheet

    @pyqtSlot(result=bool)
    def isSendingData(self):
        return self._is_sending_data

    @pyqtSlot()
    def bindSheet(self):
        """Open Google Picker to select and bind a spreadsheet."""
        if self._is_binding_sheet:
            return

        self._is_binding_sheet = True
        self.sheetBindingChanged.emit()

        def _bind():
            try:
                from utils.web_consultantsheet import run_google_picker, CancellationContext
                self._bind_cancellation_context = CancellationContext()
                
                result = run_google_picker(self._bind_cancellation_context)
                self._bind_cancellation_context = None

                if result:
                    sheet_id, sheet_name = result
                    # Save to connections (clear old version info)
                    connections = self._load_connections()
                    gs_info = connections.get('google_sheet', {})
                    gs_info['bound_sheet_id'] = sheet_id
                    gs_info['bound_sheet_name'] = sheet_name
                    gs_info.pop('sheet_ver', None)
                    gs_info.pop('arcaea_ver', None)
                    connections['google_sheet'] = gs_info
                    self._save_connections(connections)
                    
                    print(f"[SettingsHandler] Sheet bound: {sheet_name} ({sheet_id})")
                    
                    # First emit binding change so QML shows sheet name + version spinner
                    self._is_binding_sheet = False
                    self._bind_cancellation_context = None
                    self.sheetBindingChanged.emit()
                    
                    # Then fetch and save version info (spinner → version text)
                    self._fetch_and_save_sheet_versions()
                    return  # Skip finally's emit since we already emitted
                else:
                    print("[SettingsHandler] Sheet binding cancelled")
            except Exception as e:
                print(f"[SettingsHandler] Error binding sheet: {e}")
                import traceback
                traceback.print_exc()
            finally:
                self._is_binding_sheet = False
                self._bind_cancellation_context = None
                self.sheetBindingChanged.emit()

        thread = threading.Thread(target=_bind, daemon=True)
        thread.start()

    @pyqtSlot()
    def cancelBindSheet(self):
        """Cancel ongoing sheet binding."""
        # Reflect cancellation in UI immediately to avoid stale "binding" state.
        if self._is_binding_sheet:
            self._is_binding_sheet = False
            self.sheetBindingChanged.emit()

        if self._bind_cancellation_context:
            self._bind_cancellation_context.cancel()
            self._bind_cancellation_context = None

    @pyqtSlot()
    def openBoundSheet(self):
        """Open bound sheet in the default web browser."""
        connections = self._load_connections()
        gs_info = connections.get('google_sheet', {})
        bound_id = gs_info.get('bound_sheet_id', '')
        if bound_id:
            import webbrowser
            url = f"https://docs.google.com/spreadsheets/d/{bound_id}"
            webbrowser.open(url)

    @pyqtSlot()
    def sendData(self):
        """Send score data to the bound Google Sheet."""
        if self._is_sending_data:
            return

        self._is_sending_data = True
        self.sendDataStatusChanged.emit()

        def _send():
            try:
                from utils.web_consultantsheet import send_scores_to_sheet, CancellationContext
                self._send_cancellation_context = CancellationContext()
                
                connections = self._load_connections()
                gs_info = connections.get('google_sheet', {})
                sheet_id = gs_info.get('bound_sheet_id', '')
                
                if not sheet_id:
                    print("[SettingsHandler] No sheet bound for sending data")
                    return
                
                updated, total = send_scores_to_sheet(
                    sheet_id=sheet_id,
                    cancellation_context=self._send_cancellation_context
                )
                self._send_cancellation_context = None
                
                # Update last synced time
                config['sheet']['last_synced'] = str(time.time())
                print(f"[SettingsHandler] Send data complete: {updated}/{total} rows")
            except Exception as e:
                print(f"[SettingsHandler] Error sending data: {e}")
                import traceback
                traceback.print_exc()
            finally:
                self._is_sending_data = False
                self._send_cancellation_context = None
                self.sendDataStatusChanged.emit()

        thread = threading.Thread(target=_send, daemon=True)
        thread.start()


    @pyqtSlot(result=float)
    def getLastSyncedTime(self):
        """Get the last synced timestamp."""
        return config['sheet']['last_synced']

    # --- Profile Settings ---
    @pyqtSlot(result=bool)
    def getShowFriendCode(self):
        return config['profile']['show_friend_code']

    @pyqtSlot(bool)
    def setShowFriendCode(self, show):
        config['profile']['show_friend_code'] = str(show)
        self.profileDisplayChanged.emit()
        self.settingsChanged.emit()

    @pyqtSlot(result=bool)
    def getShowPotential(self):
        return config['profile']['show_potential']

    @pyqtSlot(bool)
    def setShowPotential(self, show):
        config['profile']['show_potential'] = str(show)
        self.profileDisplayChanged.emit()
        self.settingsChanged.emit()

    @pyqtSlot(result=str)
    def getProfileImage(self):
        return config['profile']['profile_image']

    @pyqtSlot(str)
    def setProfileImage(self, path):
        if path.startswith("file:///"):
            path = path[8:]
        config['profile']['profile_image'] = path.replace("\\", "/")
        self.profileDisplayChanged.emit()
        self.settingsChanged.emit()

    @pyqtSlot(result=str)
    def getProfileDescription(self):
        return config['profile']['profile_description']

    @pyqtSlot(str)
    def setProfileDescription(self, text):
        config['profile']['profile_description'] = text
        self.settingsChanged.emit()

    @pyqtSlot(result=str)
    def getGroupingCriteria(self):
        return config['profile']['grouping_criteria']

    @pyqtSlot(str)
    def setGroupingCriteria(self, criteria):
        # 'song' or 'chart'
        config['profile']['grouping_criteria'] = criteria
        self.mostPlayedOrderChanged.emit()
        self.settingsChanged.emit()

    @pyqtSlot(result=str)
    def getDifficultyFilter(self):
        return config['profile']['difficulty_filter']

    @pyqtSlot(str)
    def setDifficultyFilter(self, filters):
        # 'all' or comma separated 'pst,prs'
        config['profile']['difficulty_filter'] = filters
        self.mostPlayedOrderChanged.emit()
        self.settingsChanged.emit()

    @pyqtSlot(result=str)
    def getMostPlayedScope(self):
        return config['profile']['most_played_scope']

    @pyqtSlot(str)
    def setMostPlayedScope(self, scope):
        config['profile']['most_played_scope'] = scope
        self.mostPlayedOrderChanged.emit()
        self.settingsChanged.emit()

    # --- Account Connections ---
    def _load_connections(self):
        """Load current client account connections."""
        try:
            return load_client_connections()
        except Exception as e:
            print(f"[SettingsHandler] Error loading connections: {e}")
            return {}
    
    def _save_connections(self, connections):
        """Save current client account connections."""
        try:
            save_client_connections(connections)
        except Exception as e:
            print(f"[SettingsHandler] Error saving connections: {e}")
    
    @pyqtSlot(result=bool)
    def isArcaeaOnlineConnected(self):
        """Check if Arcaea Online is connected."""
        connections = self._load_connections()
        return connections.get('arcaea_online', {}).get('connected', False)

    @pyqtSlot(result=bool)
    def isArcaeaOnlineConnecting(self):
        return self._is_arcaea_connecting
    
    @pyqtSlot(result=bool)
    def isGoogleSheetConnected(self):
        """Check if Google Sheet is connected."""
        connections = self._load_connections()
        return connections.get('google_sheet', {}).get('connected', False)

    
    @staticmethod
    def _format_connection_date(timestamp) -> str:
        """Unix 타임스탬프(초) → 'YYYY-MM-DD HH:MM' 포맷. 누락 시 빈 문자열."""
        if not timestamp:
            return ""
        try:
            dt = datetime.fromtimestamp(timestamp)
            return dt.strftime("%Y-%m-%d %H:%M")
        except (OSError, ValueError):
            return ""

    @pyqtSlot(result='QVariant')
    def getArcaeaOnlineConnectionInfo(self):
        """Get Arcaea Online connection info as dict."""
        connections = self._load_connections()
        ao_info = connections.get('arcaea_online', {})
        if not ao_info.get('connected', False):
            return {}

        connected_at = ao_info.get('connected_at', 0)
        return {
            'connected_at': connected_at,
            'name': ao_info.get('name', ''),
            'user_id': ao_info.get('user_id', ''),
            'rating': ao_info.get('rating'),
            'join_date': ao_info.get('join_date'),
            'user_code': ao_info.get('user_code', ''),
            'formatted_date': self._format_connection_date(connected_at),
        }

    @pyqtSlot(result='QVariant')
    def getGoogleSheetConnectionInfo(self):
        """Get Google Sheet connection info as dict."""
        connections = self._load_connections()
        gs_info = connections.get('google_sheet', {})
        if not gs_info.get('connected', False):
            return {}

        connected_at = gs_info.get('connected_at', 0)
        return {
            'connected_at': connected_at,
            'user_email': gs_info.get('user_email', ''),
            'formatted_date': self._format_connection_date(connected_at),
        }
    
    @pyqtSlot()
    def connectArcaeaOnline(self):
        """Connect to Arcaea Online."""
        if self._is_arcaea_connecting:
            return

        self._is_arcaea_connecting = True
        self.arcaeaOnlineConnectionChanged.emit()

        def _connect():
            try:
                # Create a temporary ArcaeaOnline instance for login
                temp_analyzer = ArcaeaOnline()
                temp_analyzer.log = lambda msg: print(f"[ArcaeaOnline] {msg}")
                
                lang = 'ko'
                url = f'https://arcaea.lowiro.com/{lang}/profile/scores?page=1'
                
                # Initialize browser and login
                from playwright.sync_api import sync_playwright
                from utils.browser_utils import get_browser
                
                temp_analyzer.playwright = sync_playwright().start()
                temp_analyzer.browser = get_browser(temp_analyzer.playwright, headless=False)
                temp_analyzer.context = temp_analyzer.browser.new_context(
                    viewport={'width': 600, 'height': 1000}
                )
                temp_analyzer.page = temp_analyzer.context.new_page()
                
                self._arcaea_login_instance = temp_analyzer
                # Enable running status for polling loop in login()
                temp_analyzer.status.is_running = True
                
                # Setup listeners for close events
                temp_analyzer.setup_browser_listeners()

                # Perform login (this will save to account_connections.json)
                temp_analyzer.login(url)
                
                # Clean up
                temp_analyzer.stop()
                
            except Exception as e:
                print(f"[SettingsHandler] Error connecting Arcaea Online: {e}")
                import traceback
                traceback.print_exc()
            finally:
                self._is_arcaea_connecting = False
                self._arcaea_login_instance = None
                # Emit signal to update UI (on main thread)
                self.arcaeaOnlineConnectionChanged.emit()
        
        # Run in separate thread to avoid blocking UI
        thread = threading.Thread(target=_connect, daemon=True)
        thread.start()
    
    @pyqtSlot()
    def cancelArcaeaOnlineConnection(self):
        """Cancel the ongoing Arcaea Online connection process."""
        if self._arcaea_login_instance:
            print("[SettingsHandler] Cancelling Arcaea Online connection...")
            try:
                self._arcaea_login_instance.cancel()
            except Exception as e:
                print(f"[SettingsHandler] Error cancelling Arcaea instance: {e}")
            # The _connect thread will likely raise an exception or exit loop and finish

    
    @pyqtSlot()
    def disconnectArcaeaOnline(self):
        """Disconnect Arcaea Online."""
        try:
            connections = self._load_connections()
            if 'arcaea_online' in connections:
                del connections['arcaea_online']
                self._save_connections(connections)
            
            # Remove sensitive cookies from keyring
            try:
                delete_secret('sid')
            except:
                pass
            try:
                delete_secret('__stripe_sid')
            except:
                pass
            try:
                delete_secret('__stripe_mid')
            except:
                pass
            
            self.arcaeaOnlineConnectionChanged.emit()
        except Exception as e:
            print(f"[SettingsHandler] Error disconnecting Arcaea Online: {e}")
    
    @pyqtSlot()
    def connectGoogleSheet(self):
        """Connect to Google Sheet (fire-and-forget).
        
        Opens the OAuth browser page and immediately returns.
        If a previous session is in progress, it is cancelled first.
        """
        # Cancel any existing session before starting a new one
        if self._google_cancellation_context:
            print("[SettingsHandler] Cancelling previous Google Sheet session...")
            self._google_cancellation_context.cancel()
            self._google_cancellation_context = None

        def _connect():
            try:
                from utils.web_consultantsheet import get_creds, CancellationContext
                
                ctx = CancellationContext()
                self._google_cancellation_context = ctx
                
                # Pass context to get_creds
                creds = get_creds(ctx)
                
                if ctx.is_cancelled():
                    print("[SettingsHandler] Google Sheet session was superseded.")
                    return
                
                self._google_cancellation_context = None # Clear context after done
                
                if creds and creds.valid:
                    # get_creds() already saves to account_connections.json
                    print("[SettingsHandler] Google Sheet connected successfully.")
                    self.googleSheetConnectionChanged.emit()
            except Exception as e:
                print(f"[SettingsHandler] Error connecting Google Sheet: {e}")
                import traceback
                traceback.print_exc()
        
        # Run in separate thread to avoid blocking UI
        thread = threading.Thread(target=_connect, daemon=True)
        thread.start()
    
    def _cancelGoogleSheetSession(self):
        """Cancel any ongoing Google Sheet OAuth session (internal use)."""
        if self._google_cancellation_context:
            self._google_cancellation_context.cancel()
            self._google_cancellation_context = None
            
    @pyqtSlot()
    def disconnectGoogleSheet(self):
        """Disconnect Google Sheet and clear bound sheet info."""
        # Cancel any ongoing OAuth session
        self._cancelGoogleSheetSession()
        
        try:
            connections = self._load_connections()
            if 'google_sheet' in connections:
                del connections['google_sheet']
                self._save_connections(connections)
            
            # Remove sensitive tokens from keyring
            try:
                delete_secret('google_token')
            except:
                pass
            try:
                delete_secret('google_refresh_token')
            except:
                pass
            
            self.googleSheetConnectionChanged.emit()
            self.sheetBindingChanged.emit()
        except Exception as e:
            print(f"[SettingsHandler] Error disconnecting Google Sheet: {e}")

    # --- Browser Setup ---
    @pyqtSlot(result=bool)
    def isBrowserInstalled(self):
        """Check if Playwright browser is installed."""
        if self._browser_installed is None:
            from services.browser_bootstrap import is_browser_installed
            self._browser_installed = is_browser_installed()
        return self._browser_installed

    @pyqtSlot(result=bool)
    def isInstallingBrowser(self):
        return self._is_installing_browser

    @pyqtSlot()
    def installBrowser(self):
        """Install Playwright Chromium browser in background thread."""
        if self._is_installing_browser:
            return

        self._is_installing_browser = True
        self.browserInstallStatusChanged.emit()

        def worker():
            from services.browser_bootstrap import install_browser
            try:
                success, message = install_browser(
                    browser="chromium",
                    on_output=lambda line: self.browserInstallLogAdded.emit(line),
                )
                self._browser_installed = success
                if not success:
                    self.browserInstallLogAdded.emit(f"Error: {message}")
            except Exception as e:
                self._browser_installed = False
                self.browserInstallLogAdded.emit(f"Error: {e}")
            finally:
                self._is_installing_browser = False
                self.browserInstallStatusChanged.emit()

        threading.Thread(target=worker, daemon=True).start()

    @pyqtSlot()
    def recheckBrowser(self):
        """Force re-check browser installation status."""
        self._browser_installed = None
        self.browserInstallStatusChanged.emit()
