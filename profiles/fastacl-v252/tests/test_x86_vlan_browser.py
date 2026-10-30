#!/usr/bin/env python3
"""Render and exercise the standalone X86 VLAN page with an isolated mock API."""
from pathlib import Path
import json
import urllib.parse

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import expect, sync_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "test-results"
OUT.mkdir(parents=True, exist_ok=True)

state = {
    "ok": True,
    "enabled": True,
    "trunk": "eth1",
    "candidates": ["eth1"],
    "nodes": [{"id": "node-a", "name": "节点 A"}],
    "rows": [],
}
preview_rows = [
    {
        "id": "jfa25v10",
        "vlan": 10,
        "ssid": "JuLiang-10",
        "trunk": "eth1",
        "interface": "eth1.10",
        "network": "jfa25v10",
        "subnet": "192.168.10.0/24",
    },
    {
        "id": "jfa25v11",
        "vlan": 11,
        "ssid": "JuLiang-11",
        "trunk": "eth1",
        "interface": "eth1.11",
        "network": "jfa25v11",
        "subnet": "192.168.11.0/24",
    },
]

html = (ROOT / "root/usr/lib/lua/luci/view/fastacl252/vlan.htm").read_text(
    encoding="utf-8"
)
html = html.replace(
    "<%+header%>",
    '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" '
    'content="width=device-width,initial-scale=1"><base href="http://fastacl.test/">'
    "<style>body{margin:0;padding:18px;font-family:Arial,sans-serif;background:#f7f9fc}"
    "</style></head><body><main>",
)
html = html.replace("<%+footer%>", "</main></body></html>")
html = html.replace(
    '<%=url("admin/services/fastacl252_vlan_status")%>', "/cgi-bin/vlan-status"
)
html = html.replace(
    '<%=url("admin/services/fastacl252_vlan_action")%>', "/cgi-bin/vlan-action"
)
html = html.replace("<%=token%>", "test-token")

with sync_playwright() as playwright:
    try:
        browser = playwright.chromium.launch()
    except PlaywrightError:
        browser = playwright.chromium.launch(channel="chrome")
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))

    def api(route):
        if route.request.url.endswith("/cgi-bin/vlan-status"):
            route.fulfill(status=200, content_type="application/json", body=json.dumps(state))
            return
        body = route.request.post_data or ""
        payload = json.loads(urllib.parse.parse_qs(body).get("data", ["{}"])[0])
        if payload.get("action") == "preview":
            response = {"ok": True, "result": {"rows": preview_rows}}
        elif payload.get("action") == "create":
            response = {"ok": True, "result": preview_rows, "message": "VLAN 已批量创建并应用。"}
        else:
            response = {"ok": True, "result": {}}
        route.fulfill(status=200, content_type="application/json", body=json.dumps(response))

    page.route("http://fastacl.test/**", api)
    page.set_content(html, wait_until="load")

    expect(page.get_by_role("heading", name="X86 VLAN 分流")).to_be_visible()
    expect(page.locator("#vlan-summary")).to_contain_text("Trunk eth1")
    expect(page.locator("#vlan-trunk")).to_have_value("eth1")
    expect(page.locator("#vlan-node")).to_have_value("")
    page.locator("#vlan-node").select_option("node-a")

    page.get_by_role("button", name="生成预览", exact=True).click()
    expect(page.locator("#vlan-status")).to_contain_text("VLAN 10")
    expect(page.locator("#vlan-status")).to_contain_text("192.168.11.0/24")

    page.once("dialog", lambda dialog: dialog.accept())
    page.get_by_role("button", name="一键创建并应用", exact=True).click()
    expect(page.locator("#vlan-status")).to_contain_text("VLAN 已批量创建并应用")
    page.screenshot(path=str(OUT / "ui-x86-vlan-desktop.png"), full_page=True)

    page.set_viewport_size({"width": 390, "height": 844})
    assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
    expect(page.get_by_role("heading", name="X86 VLAN 分流")).to_be_visible()
    page.screenshot(path=str(OUT / "ui-x86-vlan-mobile.png"), full_page=True)
    assert not errors, errors
    browser.close()

print("X86 VLAN one-click page and responsive layout passed")
