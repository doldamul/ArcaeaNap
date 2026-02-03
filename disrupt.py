"""
페이지 상호작용 차단/복구 유틸리티

데이터 저장 중 사용자의 페이지 조작을 방지합니다.
Playwright page 객체와 함께 사용합니다.
"""


def block_pointer_events(page):
    """페이지의 포인터 이벤트를 차단합니다."""
    page.evaluate("""() => {
        const body = document.body;
        if (!body.dataset._origPointerEvents) {
            body.dataset._origPointerEvents = body.style.pointerEvents || "";
        }
        body.style.pointerEvents = "none";
    }""")


def restore_pointer_events(page):
    """페이지의 포인터 이벤트를 복구합니다."""
    page.evaluate("""() => {
        const body = document.body;
        if (body && body.dataset._origPointerEvents !== undefined) {
            body.style.pointerEvents = body.dataset._origPointerEvents;
            delete body.dataset._origPointerEvents;
        } else if (body) {
            body.style.pointerEvents = "";
        }
    }""")