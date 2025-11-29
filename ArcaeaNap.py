import time
import json
from browserdriver import get_driver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import WebDriverException

def open_arcaea_online():
    VUE_COMPONENT_SELECTOR = "#app > section > div:nth-child(3)"
    lang = 'ko'
    url = f'https://arcaea.lowiro.com/{lang}/profile/scores?page=1'
    try:
        driver = get_driver()
        assert driver is not None, "unsupported browser"

        # check login session
        login = None # TODO: get login session data from db
        if login:
            pass
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
                old_sid = None
                
            print('wait for login...')
            
            def has_sid_changed(driver):
                if not driver.window_handles:
                    raise WebDriverException("Browser closed")
                
                try:
                    cookie = driver.get_cookie('sid')
                    new_sid = cookie['value']
                except Exception as e:
                    print(f'new_sid 쿠키 읽기 오류: {e}')
                    return False
                
                if old_sid is None: 
                    return True
                
                return new_sid != old_sid
            
            WebDriverWait(driver, 300).until(has_sid_changed) # wait for manual login, timeout: 5min
            
            print('login success.')
            
            # TODO: save new_sid
        
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
            if user_scores_data:
                print(f"{len(user_scores_data)}개의 플레이 기록 발견")
                
                if __name__=='__main__':
                    print("\n데이터 샘플:")
                    print(json.dumps(user_scores_data[0], indent=2, ensure_ascii=False))

                with open('user_scores.json', 'w', encoding='utf-8') as f:
                    json.dump(user_scores_data, f, ensure_ascii=False, indent=4)
                print("\n'user_scores.json' 파일로 데이터 저장 완료")
                
            else:
                print("데이터 가져오는 중 오류 발생")

        except Exception as e:
            print(f"스크립트 실행 중 오류 발생: {e}")
            
    except Exception as e:
        print(f'브라우저 종료됨: {e}')

    finally:
        time.sleep(5) # 5초 후 브라우저 종료
        try: driver.quit()
        except: pass
    
    
if __name__=='__main__':
    open_arcaea_online()