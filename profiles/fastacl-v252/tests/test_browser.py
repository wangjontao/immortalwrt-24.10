"""Exercise the FastACL 2.8.1 UI against an isolated demo backend."""
import pathlib
import re
import threading
import traceback
from http.server import ThreadingHTTPServer

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import expect, sync_playwright

import preview_server

PACKAGE = pathlib.Path(__file__).parents[1] / "package-Makefile"
VERSION = re.search(r"^PKG_VERSION:=(.+)$", PACKAGE.read_text(), re.M).group(1)
OUT = pathlib.Path(__file__).parents[1] / "test-results"
OUT.mkdir(parents=True, exist_ok=True)

server = ThreadingHTTPServer(("127.0.0.1", 0), preview_server.Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{server.server_port}"
stage = "startup"
page = None
errors = []

try:
    with sync_playwright() as p:
        try:
            browser = p.chromium.launch()
        except PlaywrightError:
            browser = p.chromium.launch(channel="chrome")
        page = browser.new_page(viewport={"width": 1440, "height": 1080})
        page.on("pageerror", lambda error: errors.append(str(error)))

        stage = "fixed workspace navigation"
        page.goto(url)
        expect(page.get_by_text(f"V{VERSION}", exact=False)).to_be_visible()
        expect(page.get_by_role("heading", name="运行概览")).to_be_visible()
        views = page.locator(".f25-tabs > button").evaluate_all(
            "(buttons) => buttons.map((button) => button.dataset.f25View)"
        )
        assert views == ["overview", "nodes", "devices", "wifi", "settings"], views
        expect(page.locator(".f25-sticky")).to_have_css("position", "sticky")

        stage = "nodes edit copy export"
        page.locator('[data-f25-view="nodes"]').click()
        expect(page.locator(".node-row")).to_have_count(3)
        first = page.locator(".node-row").first
        for action in ("编辑", "复制", "导出", "重命名"):
            expect(first.get_by_role("button", name=action, exact=True)).to_be_visible()
        page.once("dialog", lambda dialog: dialog.accept("Renamed first node"))
        first.get_by_role("button", name="重命名", exact=True).click()
        expect(page.locator(".node-row").first.locator(".title")).to_have_text(
            "Renamed first node"
        )
        expect(page.get_by_role("button", name="导出全部", exact=True)).to_be_visible()
        page.screenshot(path=str(OUT / "ui-nodes-2.8.1.png"), full_page=True)

        stage = "node editing and notification lifetime"
        page.locator(".node-row").first.get_by_role("button", name="编辑", exact=True).click()
        expect(page.locator("#f25-node-edit-modal")).not_to_have_class(re.compile(r"\bhidden\b"))
        expect(page.locator("#f25-node-edit-json")).to_have_value(re.compile(r'"server"'))
        page.locator("#f25-node-edit-name").fill("Edited first node")
        page.locator("#f25-node-edit-save").click()
        expect(page.locator("#f25-msg")).to_contain_text("节点参数已保存并应用")
        expect(page.locator("#f25-msg")).to_have_text("", timeout=6000)

        stage = "subscriptions"
        page.get_by_role("button", name="订阅源", exact=True).click()
        page.locator("#f25-sub-name").fill("测试机场")
        page.locator("#f25-sub-url").fill("https://subscription.example.invalid/list")
        page.get_by_role("button", name="添加订阅", exact=True).click()
        expect(page.locator(".subscription-row")).to_have_count(1)
        expect(page.locator(".subscription-row .subscription-number")).to_have_text("01")
        expect(page.locator(".subscription-row .subscription-identity")).to_contain_text("测试机场")

        stage = "device counters and label-only save"
        page.locator('[data-f25-view="devices"]').click()
        expect(page.get_by_role("heading", name="单 WiFi 多设备分配模式")).to_be_visible()
        expect(page.locator("#f25-stat-total")).to_have_text("3")
        expect(page.locator("#f25-stat-online")).to_have_text("2")
        expect(page.locator(".device-online.is-online")).to_have_count(2)
        expect(page.locator(".device-online.is-offline")).to_have_count(1)
        device = page.locator("#f25-devices .item").nth(1)
        device.get_by_role("textbox").first.fill("办公室手机")
        device.get_by_role("button", name="保存备注", exact=True).click()
        expect(device.locator(".device-title")).to_contain_text("办公室手机")

        stage = "main LAN assignment and collapsible panels"
        page.locator('[data-f25-view="wifi"]').click()
        expect(page.get_by_role("heading", name="多 WiFi 分配模式")).to_be_visible()
        main_panel = page.locator("#f25-main-lan-panel")
        expect(main_panel).to_have_attribute("open", "")
        expect(page.locator("#f25-main-lan-node")).to_be_visible()
        expect(page.locator("#f25-main-lan-pre")).to_be_visible()
        expect(page.locator("#f25-main-lan-dns")).to_be_visible()
        main_panel.locator(":scope > summary").click()
        expect(page.locator("#f25-main-lan-fields")).not_to_be_visible()
        main_panel.locator(":scope > summary").click()
        page.locator("#f25-main-lan-node").select_option("us")
        page.locator("#f25-main-lan-pre").select_option("front")
        page.locator("#f25-main-lan-save").click()
        expect(page.locator("#f25-msg")).to_contain_text("默认出口已更新")

        stage = "WiFi creation and panel collapse"
        page.locator("#f25-wifi-create-panel > summary").click()
        page.locator("#f25-w5").fill("1")
        page.locator("#f25-w2").fill("1")
        page.locator("#f25-wprefix").fill("AP")
        page.get_by_role("button", name="批量建立 WiFi", exact=True).click()
        expect(page.locator("#f25-msg")).to_contain_text("WiFi 拓扑已保存", timeout=10000)
        expect(page.locator("#f25-wifis .item")).to_have_count(2)
        existing = page.locator("#f25-wifi-existing-panel")
        existing.locator(":scope > summary").click()
        expect(page.locator("#f25-wifis")).not_to_be_visible()
        existing.locator(":scope > summary").click()
        expect(page.locator("#f25-wifis")).to_be_visible()
        page.screenshot(path=str(OUT / "ui-wifi-2.8.1.png"), full_page=True)

        stage = "DNS and dataplane settings"
        page.locator('[data-f25-view="settings"]').click()
        page.locator("#f25-proxy-dns").select_option("google")
        page.get_by_role("button", name="保存 DNS", exact=True).click()
        expect(page.locator("#f25-msg")).to_contain_text("应用层快速切换完成")
        page.get_by_role("button", name="转发方式", exact=True).click()
        expect(page.locator("#f25-dataplane")).to_have_value("singbox")
        expect(page.locator("#f25-tun-interface")).to_have_value("fastacl-tun0")
        expect(page.get_by_role("button", name="应用数据面", exact=True)).to_be_visible()

        stage = "responsive screenshots"
        page.locator('[data-f25-view="overview"]').click()
        page.screenshot(path=str(OUT / "ui-desktop-2.8.1.png"), full_page=True)
        page.set_viewport_size({"width": 390, "height": 844})
        expect(page.get_by_role("heading", name="运行概览")).to_be_visible()
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
        page.screenshot(path=str(OUT / "ui-mobile-2.8.1.png"), full_page=True)
        page.locator('[data-f25-view="wifi"]').click()
        expect(page.get_by_role("heading", name="多 WiFi 分配模式")).to_be_visible()
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
        page.screenshot(path=str(OUT / "ui-mobile-wifi-2.8.1.png"), full_page=True)
        assert not errors, errors
        browser.close()
        print(f"FastACL V{VERSION} navigation, node tools, main LAN, 3s notice and responsive UI passed")
except Exception:
    detail = "stage: " + stage + "\n\n" + traceback.format_exc() + "\npage errors:\n" + "\n".join(errors)
    (OUT / "ui-browser-error.txt").write_text(detail, encoding="utf-8")
    if page is not None:
        try:
            page.screenshot(path=str(OUT / "ui-browser-failure.png"), full_page=True)
        except Exception:
            pass
    print(detail)
    raise
finally:
    server.shutdown()
    server.server_close()
