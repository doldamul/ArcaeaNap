import configparser
import copy
import os
import tempfile
import threading
import time
from enum import StrEnum, auto

from utils.user_paths import get_user_data_dir, get_app_root

class OS(StrEnum):
    WINDOWS = auto(),
    MACOS = auto(),
    LINUX = auto()

config = None

_SAVE_RETRY_DELAYS = (0.05, 0.1, 0.2, 0.4)


class _ReplacePermissionError(PermissionError):
    """PermissionError raised specifically by the atomic destination replace."""

    def __init__(self, original):
        self.original = original
        super().__init__(*original.args)

_config_default = {
    'general': {
        'cache_path': './arcaea_nap_data/',
        'song_title_language': 'en',  # 'en' or 'jp'
        'theme_mode': 'system',  # 'system', 'light', or 'dark'
    },
    'profile': {
        'show_friend_code': True,
        'show_potential': False,
        'show_name': True,
        'show_description': True,
        'show_play_count_time': True,
        'play_stats_diff_filter': 'all',
        'show_play_count_most_played': True,
        'profile_image': '',
        'profile_description': '',
        'grouping_criteria': 'song',  # 'song' or 'chart'
        'difficulty_filter': 'all',  # 'all' or comma-separated string like 'pst,prs'
        'most_played_scope': 'total',  # 'total' or 'this_year'
    },
    'sheet': {
        'last_synced': 0,
    },
    'statistics': {
        'best_potential_mark': 'none',  # 'none' | '10' | '30' | '50' | '100' | 'all'
    },
}

def resolve_cache_path(v: str) -> str:
    """Resolve a (possibly './'-relative) cache_path value to an absolute path.

    Single source of truth for cache-path resolution — used by config validation,
    the settings UI (open/change folder), AND the actual data read/write sites
    (via get_cache_dir), so they all agree on where the cache actually lives.

    './'-relative paths resolve against:
      - macOS: the user-data dir (~/Library/Application Support/ArcaeaNap) — mutable
        data cannot live inside the .app bundle;
      - other OS: the app root (install folder when frozen, repo root in dev) — NOT
        the volatile CWD nor __file__ (which is lib/utils inside a frozen build).
    Absolute paths are returned as-is (normalized).
    """
    if v.startswith('./') or v.startswith('.\\'):
        _udd = get_user_data_dir()
        base_dir = _udd if _udd else get_app_root()
        return os.path.normpath(os.path.join(base_dir, v))
    return os.path.abspath(v)


def get_cache_dir() -> str:
    """Absolute, CWD-independent cache directory (single source of truth).

    All actual data read/write sites must use this instead of the raw
    config['general']['cache_path'] value (which is a './'-relative string and
    would otherwise resolve against the volatile current working directory)."""
    return resolve_cache_path(config['general']['cache_path'])


def _validate_cache_path(v: str) -> str:
    """
    Validate and normalize cache_path.
    Supports './'-relative paths, resolved via resolve_cache_path (macOS user-data dir,
    else the app root). Creates the resolved directory if it doesn't exist.
    """
    abs_path = resolve_cache_path(v)

    # Create directory if it doesn't exist
    if not os.path.isdir(abs_path):
        try:
            os.makedirs(abs_path, exist_ok=True)
        except OSError as e:
            raise ValueError(f'Cannot create directory: {abs_path} ({e})')
    
    # Return the original value (preserving relative path format in config)
    return v


def _validate_song_title_language(v: str) -> str:
    value = str(v).strip().lower()
    if value not in ('en', 'jp'):
        raise ValueError("song_title_language must be 'en' or 'jp'")
    return value


def _validate_theme_mode(v: str) -> str:
    value = str(v).strip().lower()
    if value not in ('system', 'light', 'dark'):
        raise ValueError("theme_mode must be 'system', 'light', or 'dark'")
    return value

_converters = {
    'general': {
        'cache_path': _validate_cache_path,
        'song_title_language': _validate_song_title_language,
        'theme_mode': _validate_theme_mode,
    },
    'profile': {
        'show_friend_code': lambda v: v.lower() == 'true',
        'show_potential': lambda v: v.lower() == 'true',
        'show_name': lambda v: v.lower() == 'true',
        'show_description': lambda v: v.lower() == 'true',
        'show_play_count_time': lambda v: v.lower() == 'true',
        'play_stats_diff_filter': str,
        'show_play_count_most_played': lambda v: v.lower() == 'true',
        'profile_image': str,
        'profile_description': str,
        'grouping_criteria': str,
        'difficulty_filter': str,
        'most_played_scope': str,
    },
    'sheet': {
        'last_synced': float,
    },
    'statistics': {
        'best_potential_mark': str,
    },
}

# --- Runtime-only settings (not persisted to config.ini) ---
_runtime_default = {
    'general': {
        'analyze_mode': False,
    }
}

def singleton(cls):
    instances = {}

    def get_instance(*args, **kwargs):
        if cls not in instances:
            instances[cls] = cls(*args, **kwargs)
        return instances[cls]

    return get_instance

class SectionWrapper:
    def __init__(self, parent, section_name, section_proxy):
        self.parent = parent
        self.section_name = section_name
        self.section_proxy = section_proxy

    def _is_runtime_key(self, key):
        return key in _runtime_default.get(self.section_name, {})

    def transform_value(self, section, key, value):
        converter = _converters.get(section, {}).get(key)
        
        try:
            return converter(value)
        except Exception as e:
            print(f"[Config Warning] Conversion failed for [{section}] {key}={value}: {e}\nfallback to default configuration")
            return _config_default[section][key]

    def __getitem__(self, key):
        # Runtime keys: read directly from in-memory store (no conversion needed)
        if self._is_runtime_key(key):
            return self.parent.get_runtime(self.section_name, key)

        raw_value = self.section_proxy[key]
        return self.transform_value(self.section_name, key, raw_value)

    def __setitem__(self, key, value):
        # Runtime keys: store in memory only (no file save)
        if self._is_runtime_key(key):
            self.parent.set_runtime(self.section_name, key, value)
            return True

        with self.parent._save_lock:
            parser = self.parent._config
            serialized_value = str(value)
            had_raw_option = parser.has_option(self.section_name, key)
            previous_raw_value = (
                parser.get(self.section_name, key, raw=True)
                if had_raw_option
                else None
            )
            if had_raw_option and previous_raw_value == serialized_value:
                return False

            self.section_proxy[key] = serialized_value
            try:
                self.parent.save()
            except Exception:
                if had_raw_option:
                    parser.set(self.section_name, key, previous_raw_value)
                else:
                    parser.remove_option(self.section_name, key)
                raise
            return True

@singleton
class Configuration:
    _config: configparser.ConfigParser
    filename: str = "config.ini"

    def __init__(self) -> None:
        # config.ini lives at a stable, CWD-independent location: the user-data dir
        # on macOS, else the app root (install folder / repo root). Previously it was
        # a bare "config.ini" (CWD-relative), which broke when the app was launched
        # with a different working directory (e.g. after an update relaunch).
        _udd = get_user_data_dir()
        base = _udd if _udd else get_app_root()
        self.filename = os.path.join(base, "config.ini")
        self._config = configparser.ConfigParser()
        self._runtime = copy.deepcopy(_runtime_default)
        self._save_lock = threading.RLock()
        
        if not os.path.exists(self.filename):
            # create config file as default
            self._config.read_dict(_config_default)
            self.save()
        else:
            self._config.read(self.filename, encoding="utf-8")
            self._sanitize_config()
            
        if __name__=='__main__':
            print(f'data validation: {self._is_valid_structure()}')

    def get_runtime(self, section, key):
        return self._runtime.get(section, {}).get(key, _runtime_default.get(section, {}).get(key))

    def set_runtime(self, section, key, value):
        if section not in self._runtime:
            self._runtime[section] = {}
        self._runtime[section][key] = value
        
    def __getitem__(self, key):
        if key not in self._config:
            self._config.add_section(key)
            
        return SectionWrapper(self, key, self._config[key])

    def _sanitize_config(self) -> None:
        """
        Sanitize the loaded config:
        1. Remove sections/keys not in _config_default
        2. Add missing keys with default values
        3. Validate existing keys and restore defaults for invalid values
        """
        modified = False
        
        # Remove unknown sections
        for section in self._config.sections():
            if section not in _config_default:
                self._config.remove_section(section)
                print(f"[Config] Removed unknown section: [{section}]")
                modified = True
        
        # For each expected section
        for section, default_keys in _config_default.items():
            # Add missing section
            if not self._config.has_section(section):
                self._config.add_section(section)
                print(f"[Config] Added missing section: [{section}]")
                modified = True
            
            # Remove unknown keys from this section
            if self._config.has_section(section):
                for key in list(self._config[section].keys()):
                    if key not in default_keys:
                        self._config.remove_option(section, key)
                        print(f"[Config] Removed unknown key: [{section}] {key}")
                        modified = True
            
            # Add missing keys with default values
            for key, default_value in default_keys.items():
                if not self._config.has_option(section, key):
                    self._config.set(section, key, str(default_value))
                    print(f"[Config] Restored missing key: [{section}] {key} = {default_value}")
                    modified = True
                else:
                    # Validate existing value
                    raw_value = self._config.get(section, key)
                    converter = _converters.get(section, {}).get(key)
                    if converter:
                        try:
                            converter(raw_value)
                        except Exception:
                            self._config.set(section, key, str(default_value))
                            print(f"[Config] Restored invalid value: [{section}] {key} = {default_value} (was: {raw_value})")
                            modified = True
        
        if modified:
            self.save()

    def _is_valid_structure(self) -> bool:
        for section, keys in _config_default.items():
            if not self._config.has_section(section):
                return False
            for key in keys:
                if not self._config.has_option(section, key):
                    return False
        return True

    def _save_once(self, destination_dir):
        temp_path = None
        temp_file = None
        try:
            temp_file = tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=destination_dir,
                prefix=".config-",
                suffix=".tmp",
                delete=False,
            )
            temp_path = temp_file.name
            self._config.write(temp_file)
            temp_file.flush()
            os.fsync(temp_file.fileno())
            temp_file.close()
            temp_file = None
            try:
                os.replace(temp_path, self.filename)
            except PermissionError as error:
                raise _ReplacePermissionError(error) from error
            temp_path = None
        finally:
            if temp_file is not None:
                temp_file.close()
            if temp_path is not None:
                try:
                    os.unlink(temp_path)
                except OSError:
                    pass

    def save(self):
        """Atomically persist config, tolerating brief external file locks."""
        destination_dir = os.path.dirname(os.path.abspath(self.filename)) or os.curdir
        with self._save_lock:
            for attempt, delay in enumerate((*_SAVE_RETRY_DELAYS, None)):
                try:
                    self._save_once(destination_dir)
                    return
                except _ReplacePermissionError as error:
                    if delay is None:
                        raise error.original.with_traceback(error.original.__traceback__)
                    time.sleep(delay)

config = Configuration()

if __name__=='__main__':
    print(Configuration())
