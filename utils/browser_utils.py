"""
Playwright 브라우저 유틸리티 모듈

Selenium의 browserdriver.py를 대체하며, 설치된 Playwright 브라우저를 자동 감지합니다.
"""

from playwright.sync_api import Playwright, Browser


def get_browser(playwright: Playwright, headless: bool = False) -> Browser:
    """
    설치된 Playwright 브라우저 중 하나를 반환합니다.
    
    우선순위: chromium > firefox > webkit
    
    Args:
        playwright: Playwright 인스턴스
        headless: 헤드리스 모드 여부
    
    Returns:
        Browser: 실행된 브라우저 인스턴스
    
    Raises:
        RuntimeError: 설치된 브라우저가 없는 경우
    """
    # 자동화 감지 회피를 위한 브라우저 인수
    stealth_args = [
        '--disable-blink-features=AutomationControlled',
        '--disable-infobars',
        '--disable-dev-shm-usage',
        '--no-first-run',
        '--no-default-browser-check',
    ]
    
    browser_types = [
        ("chromium", playwright.chromium),
        ("firefox", playwright.firefox),
        ("webkit", playwright.webkit),
    ]
    
    errors = []
    for name, browser_type in browser_types:
        try:
            # Firefox는 args 지원 안함
            if name == "firefox":
                return browser_type.launch(headless=headless)
            else:
                return browser_type.launch(headless=headless, args=stealth_args)
        except Exception as e:
            errors.append(f"{name}: {e}")
            continue
    
    error_details = "\n".join(errors)
    raise RuntimeError(
        f"No Playwright browser installed.\n"
        f"Run 'playwright install chromium' (or firefox/webkit) first.\n"
        f"Errors:\n{error_details}"
    )
