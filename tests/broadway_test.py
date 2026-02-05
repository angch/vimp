from playwright.sync_api import Page, expect, sync_playwright
import sys

def test_vimp_loads(page: Page):
    print("Navigating to Broadway server...")
    # Connect to Broadway (Default port for :5 is 8085)
    page.goto("http://localhost:8085")

    print("Waiting for canvas...")
    # Broadway renders the GTK surface on a canvas
    page.wait_for_selector("canvas", timeout=5000)

    # Take screenshot
    print("Taking screenshot...")
    page.screenshot(path="tests/vimp_broadway_screenshot.png")

    # Basic assertion that we loaded something
    title = page.title()
    print(f"Page Title: {title}")
    # Broadway usually sets title to "Broadway" or window title

    # Check if canvas is visible
    expect(page.locator("canvas")).to_be_visible()

if __name__ == "__main__":
    with sync_playwright() as p:
        print("Launching browser...")
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        try:
            test_vimp_loads(page)
            print("Test Passed!")
        except Exception as e:
            print(f"Test Failed: {e}")
            sys.exit(1)
        finally:
            browser.close()
