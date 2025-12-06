def block_pointer_events(driver):
    driver.execute_script("""
        const body = document.body;
        if (!body.dataset._origPointerEvents) {
            body.dataset._origPointerEvents = body.style.pointerEvents || "";
        }
        body.style.pointerEvents = "none";
    """)

def restore_pointer_events(driver):
    driver.execute_script("""
        const body = document.body;
        if (body && body.dataset._origPointerEvents !== undefined) {
            body.style.pointerEvents = body.dataset._origPointerEvents;
            delete body.dataset._origPointerEvents;
        } else if (body) {
            body.style.pointerEvents = "";
        }
    """)
    
if __name__=='__main__':
    from browserdriver import get_driver
    import time
    driver = get_driver()
    url = f'https://www.google.com/'
    driver.get(url)
    
    time.sleep(5)
    block_pointer_events(driver)
    time.sleep(10)
    restore_pointer_events(driver)
    time.sleep(10)
    