import configparser
import copy
import os
from enum import StrEnum, auto

class OS(StrEnum):
    WINDOWS = auto(),
    MACOS = auto(),
    LINUX = auto()

config = None

_config_default = {
    'general': {
        'cache_path': './arcaea_nap_data/',
        'song_title_language': 'en',  # 'en' or 'jp'
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
    }
}

def _validate_cache_path(v: str) -> str:
    """
    Validate and normalize cache_path.
    Supports relative paths like './...' which are resolved relative to the script directory.
    Creates the directory if it doesn't exist.
    """
    # Resolve relative paths from the script's directory
    if v.startswith('./') or v.startswith('.\\'):
        base_dir = os.path.dirname(os.path.abspath(__file__))
        abs_path = os.path.normpath(os.path.join(base_dir, v))
    else:
        abs_path = os.path.abspath(v)
    
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

_converters = {
    'general': {
        'cache_path': _validate_cache_path,
        'song_title_language': _validate_song_title_language,
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
    }
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
            return

        self.section_proxy[key] = str(value)
        self.parent.save()

@singleton
class Configuration:
    _config: configparser.ConfigParser
    filename: str = "config.ini"

    def __init__(self) -> None:
        self._config = configparser.ConfigParser()
        self._runtime = copy.deepcopy(_runtime_default)
        
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

    def save(self):
        # Always save to the root directory (consistent location)
        with open(self.filename, 'w', encoding='utf-8') as f:
            self._config.write(f)

config = Configuration()

if __name__=='__main__':
    print(Configuration())