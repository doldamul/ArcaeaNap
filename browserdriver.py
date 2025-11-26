from selenium import webdriver
from selenium_stealth import stealth
import platform
get_browser_name_os = None # function variable
os = None

# TODO: get preferred browser name from preferences
# currently just uses default browser
# TODO: add firefox support
def get_driver():
    driver = None
    
    match get_browser_name():
        case 'chrome':
            driver = webdriver.Chrome()
        case 'edge':
            driver = webdriver.Edge()
        case 'unsupported':
            return None
    
    b_info = get_browser_info()
    stealth(driver, **b_info)
    
    return driver

def get_browser_info():
    b_info = {}
    data = {}
    # TODO: save/load graphics info from database
    # data = get_from_DB(f'{get_browser_name()}_graphics_info')
    (cont, lang) = 'ko-KR', 'ko'
    
    b_info['languages']    = [cont, lang, 'en-US', 'en'] if (cont, lang) != ('en-US', 'en') else ['en-US', 'en']
    b_info['vendor']       = 'Google Inc.' # '' if get_browser_name() == 'firefox' else 'Google Inc.'
    b_info['platform']     = os
    b_info['fix_hairline'] = True
    
    if data:
        b_info['webgl_vendor'] = data['webgl_vendor']
        b_info['renderer'] = data['renderer']
    else:
        # execute dummy browser to get graphics renderer info
        driver = None
    
        match get_browser_name():
            case 'chrome':
                options = webdriver.ChromeOptions()
                options.add_argument('--start-minimized')
                driver = webdriver.Chrome(options=options)
            case 'edge':
                options = webdriver.EdgeOptions()
                options.add_argument('--start-minimized')
                driver = webdriver.Edge(options=options)
            case 'unsupported':
                return None

        try:
            driver.get("about:blank")
            
            js_code = """
            var canvas = document.createElement('canvas');
            var gl = canvas.getContext('webgl') || canvas.getContext('experimental-webgl');
            var debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
            
            var webgl_vendor = gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL);
            var renderer = gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL);
            
            return {webgl_vendor: webgl_vendor, renderer: renderer};
            """
            
            data = driver.execute_script(js_code)
            
            b_info['webgl_vendor'] = data['webgl_vendor']
            b_info['renderer'] = data['renderer']
            
        except Exception as e:
            print(f"GPU info extraction failed: {e}")
            
            # default value when fails
            b_info['webgl_vendor'] = "Intel Inc."
            b_info['renderer'] = "Intel Iris OpenGL Engine"
        finally:
            driver.quit()
    
    if __name__=='__main__':
        print(b_info)
    
    return b_info
    

# 'chrome', 'edge', 'firefox', 'unsupported'
def get_browser_name() -> str:
    browser = get_browser_name_os().lower()
    
    if 'chrome' in browser:
        return 'chrome'
    elif 'edge' in browser:
        return 'edge'
    # elif 'firefox' in browser:
    #     return 'firefox'
    else:
        return 'unsupported'
    
def get_browser_name_windows():
    import winreg
    from winreg import OpenKey, QueryValueEx, HKEY_CURRENT_USER
    reg_path = r"Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice"
    with OpenKey(HKEY_CURRENT_USER, reg_path) as key:
        progid, _ = QueryValueEx(key, "ProgId")
        
    command_path = f"{progid}\\shell\\open\\command"
    with winreg.OpenKey(winreg.HKEY_CLASSES_ROOT, command_path) as key:
            cmd_string, _ = winreg.QueryValueEx(key, '')
        
    return cmd_string

def get_browser_name_darwin():
    import plistlib
    import subprocess

    plist_path = '~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist'
    plist_path = plist_path.replace('~', subprocess.check_output('echo ~', shell=True).decode().strip())
    with open(plist_path, 'rb') as f:
        pl = plistlib.load(f)
    for h in pl.get('LSHandlers', []):
        if h.get('LSHandlerURLScheme') == 'http':
            return h.get('LSHandlerRoleAll')
    return None

def get_browser_name_linux():
    import subprocess
    
    result = subprocess.run(['xdg-settings', 'get', 'default-web-browser'], capture_output=True, text=True)
    return result.stdout.strip()
    
        
system = platform.system()
match system:
    case 'Windows':
        get_browser_name_os = get_browser_name_windows
        os = 'Win32'
    case 'Darwin': # macOS
        get_browser_name_os = get_browser_name_darwin
        os = 'MacIntel'
    case 'Linux':
        get_browser_name_os = get_browser_name_linux
        os = 'Linux x86_64'
    case _:
        print(f"error: {system} is not supported")
        exit(1)
        

if __name__=='__main__':
    print(get_driver())