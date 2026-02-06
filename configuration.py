import configparser
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
        'analyze_mode': False,
    },
    'profile': {
        'show_friend_code': True,
        'show_potential': False,
        'profile_image': '',
        'profile_description': '',
        'grouping_criteria': 'song',  # 'song' or 'chart'
        'difficulty_filter': 'all',  # 'all' or comma-separated string like 'pst,prs'
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

_converters = {
    'general': {
        'cache_path': _validate_cache_path,
        'analyze_mode': lambda v: v.lower() == 'true',
    },
    'profile': {
        'show_friend_code': lambda v: v.lower() == 'true',
        'show_potential': lambda v: v.lower() == 'true',
        'profile_image': str,
        'profile_description': str,
        'grouping_criteria': str,
        'difficulty_filter': str,
    },
    'sheet': {
        'last_synced': float,
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

    def transform_value(self, section, key, value):
        converter = _converters.get(section, {}).get(key)
        
        try:
            return converter(value)
        except Exception as e:
            print(f"[Config Warning] Conversion failed for [{section}] {key}={value}: {e}\nfallback to default configuration")
            return _config_default[section][key]

    def __getitem__(self, key):
        raw_value = self.section_proxy[key]
    
        return self.transform_value(self.section_name, key, raw_value)

    def __setitem__(self, key, value):
        self.section_proxy[key] = str(value)
        self.parent.save()

@singleton
class Configuration:
    _config: configparser.ConfigParser
    filename: str = "config.ini"

    def __init__(self) -> None:
        self._config = configparser.ConfigParser()
        
        if not os.path.exists(self.filename):
            # create config file as default
            self._config.read_dict(_config_default)
            self.save()
        else:
            self._config.read(self.filename, encoding="utf-8")
            self._sanitize_config()
            
        if __name__=='__main__':
            print(f'data validation: {self._is_valid_structure()}')
        
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