import configparser
import os
from enum import StrEnum, auto

class Browser(StrEnum):
    SYSTEM_DEFAULT = auto()
    CHROME = auto()
    EDGE = auto()
    # FIREFOX = auto()

class OS(StrEnum):
    WINDOWS = auto(),
    MACOS = auto(),
    LINUX = auto()

config = None

_config_default = {
    'general': {
        'browser': Browser.CHROME,
        'auto_login': True,
        'cache_path': './'
    }
}

_converters = {
    'general': {
        'browser': Browser,
        'auto_login': lambda v: v.lower() == 'true',
        'cache_path': lambda v: (_ for _ in ()).throw(ValueError(f'invalid path: {v}')) if os.path.isdir(os.path.dirname(v)) else v
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
    
        return self.parent.transform_value(self.section_name, key, raw_value)

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
            # TODO: restore when the data corrupted
            
        if __name__=='__main__':
            print(f'data validation: {self._is_valid_structure()}')
        
    def __getitem__(self, key):
        if key not in self._config:
            self._config.add_section(key)
            
        return SectionWrapper(self, self._config[key])

    def _is_valid_structure(self) -> bool:
        for section, keys in _config_default.items():
            if not self._config.has_section(section):
                return False
            for key in keys:
                if not self._config.has_option(section, key):
                    return False
        return True

    def save(self):
        with open(self.filename, 'w', encoding='utf-8') as f:
            self._config.write(f)

config = Configuration()

if __name__=='__main__':
    print(Configuration())