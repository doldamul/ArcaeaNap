from configuration import config
import keyring
import time
import json
import os
from browserdriver import get_driver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

def open_arcaea_online():
    VUE_COMPONENT_SELECTOR = "#app > section > div:nth-child(3)"
    lang = 'ko'
    url = f'https://arcaea.lowiro.com/{lang}/profile/scores?page=1'
    login_filename = 'login.dat'
    try:
        driver = get_driver()
        assert driver is not None, "unsupported browser"

        # check login session
        login_filepath = os.path.join(config['general']['cache_path'], login_filename)
        login = os.path.exists(login_filepath) and os.path.isfile(login_filepath) and config['general']['auto_login']
        if login:
            with open(login_filepath, 'r', encoding='utf-8') as f:
                login_cookies = json.load(f)
            
            driver.execute_cdp_cmd('Network.enable', {})
            
            for cookie in login_cookies:
                try:
                    match cookie['name']:
                        case 'sid':
                            cookie['value'] = keyring.get_password('ArcaeaNap', 'sid')
                        case '__stripe_sid':
                            cookie['value'] = keyring.get_password('ArcaeaNap', '__stripe_sid')
                        case '__stripe_mid':
                            cookie['value'] = keyring.get_password('ArcaeaNap', '__stripe_mid')
                        case _:
                            pass
                    
                    driver.execute_cdp_cmd('Network.setCookie', cookie)
                except Exception as e:
                    print(f'쿠키 주입 도중 문제 발생: {e}')
            
            driver.execute_cdp_cmd('Network.disable', {})
            
            driver.get(url)
        else:
            new_sid = None
            driver.get(url)
            
            # wait until cookie loaded
            WebDriverWait(driver, 30).until(
                lambda driver: driver.get_cookie('sid') is not None
            )
            
            try:
                cookie = driver.get_cookie('sid')
                old_sid = cookie['value']
            except Exception as e:
                print(f'old_sid 쿠키 읽기 오류: {e}')
                raise
                
            print('wait for login...')
            
            def has_sid_changed(driver):
                try:
                    cookie = driver.get_cookie('sid')
                    new_sid = cookie['value']
                except Exception as e:
                    print(f'new_sid 쿠키 읽기 오류: {e}')
                    raise
                
                return new_sid != old_sid
            
            WebDriverWait(driver, 300).until(has_sid_changed) # wait for manual login, timeout: 5min
            WebDriverWait(driver, 30).until(
                EC.presence_of_element_located((By.CSS_SELECTOR, VUE_COMPONENT_SELECTOR))
            )
            
            print('login success.')
            
            # save login session
            LOGIN_COOKIE = {'sid', '__stripe_sid', '__stripe_mid'}
            SUB_COOKIE = {'_ga', 'ctrcode', 'lang'}
            COOKIE_ESSENTIAL_FIELDS = {'name', 'value', 'domain', 'path', 'expires', 'expiry', 'httpOnly', 'secure', 'sameSite'}
            
            data = get_all_cookies_chromium(driver)
            cookies = []
            
            for cookie in data:
                if cookie['name'] in LOGIN_COOKIE:
                    keyring.set_password('ArcaeaNap', cookie['name'], cookie['value'])
                    cookie['value'] = ''
                elif not any(name in cookie['name'] for name in SUB_COOKIE):
                    continue
                
                cookies.append({k: v for k, v in cookie.items() if k in COOKIE_ESSENTIAL_FIELDS})
            
            if __name__=='__main__':
                print(cookies)
            
            with open(login_filepath, 'w', encoding='utf-8') as f:
                json.dump(cookies, f, ensure_ascii=False)
        
        # get content (TODO: auto repeat when it detects new page) 
        try:        
            # wait until content loaded
            wait = WebDriverWait(driver, 30)
            
            target_element = wait.until(
                EC.presence_of_element_located((By.CSS_SELECTOR, VUE_COMPONENT_SELECTOR))
            )
            
            user_scores_data = driver.execute_script(
                "return arguments[0].__vue__.userScores;", # javascript
                target_element
            )

            # save as json
            score_filename = 'user_scores.json'
            score_filepath = os.path.join(config['general']['cache_path'], score_filename)
            if user_scores_data:
                print(f"{len(user_scores_data)}개의 플레이 기록 발견")
                
                if __name__=='__main__':
                    print("\n데이터 샘플:")
                    print(json.dumps(user_scores_data[0], indent=2, ensure_ascii=False))

                with open(score_filepath, 'w', encoding='utf-8') as f:
                    json.dump(user_scores_data, f, ensure_ascii=False, indent=4)
                print(f"\n'{score_filename}' 파일로 데이터 저장 완료")
                
            else:
                print("데이터 가져오는 중 오류 발생")

        except Exception as e:
            print(f"스크립트 실행 중 오류 발생: {e}")
            
    except Exception as e:
        print(f'브라우저 종료됨: {e}')

    finally:
        time.sleep(5) # 5초 후 브라우저 종료 (TODO: 종료 전 변경된 쿠키 확인 후 업데이트?)
        try: driver.quit()
        except: pass

def get_all_cookies_chromium(driver):
    try:
        driver.execute_cdp_cmd('Network.enable', {})
        result = driver.execute_cdp_cmd('Network.getAllCookies', {})
        cookies = result['cookies']
    except Exception as e:
        print(f'cdp로부터 쿠키 가져오는 중 오류 발생: {e}')
        raise
    finally:
        try: driver.execute_cdp_cmd('Network.disable', {})
        except: pass
    
    target_cookies = []
    for cookie in cookies:
        if 'lowiro.com' in cookie['domain']:
            target_cookies.append(cookie)
            
    return target_cookies    
    
if __name__=='__main__':
    open_arcaea_online()