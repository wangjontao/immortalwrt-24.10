#!/usr/bin/env python3
"""Verify the custom DNS editor stays on the JuLiang dark surface."""
import pathlib
import threading
from http.server import ThreadingHTTPServer

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import expect, sync_playwright

import preview_server


OUT = pathlib.Path(__file__).parents[1] / "test-results"
OUT.mkdir(parents=True, exist_ok=True)

server = ThreadingHTTPServer(("127.0.0.1", 0), preview_server.Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()

try:
    with sync_playwright() as playwright:
        try:
            browser = playwright.chromium.launch()
        except PlaywrightError:
            browser = playwright.chromium.launch(channel="chrome")
        page = browser.new_page(viewport={"width": 1280, "height": 900})
        page.goto(f"http://127.0.0.1:{server.server_port}")
        page.locator('[data-f25-view="wifi"]').click()
        page.locator("#f25-main-lan-node").select_option("us")
        page.locator("#f25-main-lan-dns").select_option("custom")

        editor = page.locator(".main-lan-dns-custom")
        expect(editor).to_be_visible()
        styles = editor.evaluate(
            """element => ({
                background: getComputedStyle(element).backgroundImage,
                title: getComputedStyle(element.querySelector(".wifi-dns-custom-title")).color
            })"""
        )
        assert "rgb(12, 34, 50)" in styles["background"], styles
        assert "rgb(16, 39, 56)" in styles["background"], styles
        assert styles["title"] == "rgb(167, 247, 255)", styles
        page.screenshot(path=str(OUT / "ui-custom-dns-dark.png"), full_page=True)
        browser.close()
        print("PASS custom DNS dark surface")
finally:
    server.shutdown()
    server.server_close()
