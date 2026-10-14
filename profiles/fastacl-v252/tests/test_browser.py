"""Exercise the responsive dev.2 UI against an isolated demo backend."""
import pathlib, threading
from http.server import ThreadingHTTPServer
from playwright.sync_api import sync_playwright, expect
import preview_server

server=ThreadingHTTPServer(('127.0.0.1',0),preview_server.Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
url=f'http://127.0.0.1:{server.server_port}'
try:
    with sync_playwright() as p:
        browser=p.chromium.launch();page=browser.new_page(viewport={'width':1440,'height':1080});errors=[]
        page.on('pageerror',lambda e:errors.append(str(e)))
        page.goto(url)
        expect(page.locator('#f25-devices .device')).to_have_count(3)
        expect(page.get_by_text('多 WiFi 管理',exact=True)).to_be_visible()
        expect(page.locator('#f25-direct-dns')).to_have_value('alidns');expect(page.locator('#f25-proxy-dns')).to_have_value('cloudflare')
        page.locator('#f25-proxy-dns').select_option('google');page.get_by_role('button',name='保存 DNS',exact=True).click();expect(page.get_by_role('status')).to_contain_text('已保存',timeout=10000)
        page.locator('#f25-links').fill('socks5://user:pass@proxy.example:1080#US\nproxy2.example:1080:user:pass')
        page.get_by_role('button',name='导入节点',exact=True).click();expect(page.get_by_role('status')).to_contain_text('成功导入 2 个节点',timeout=10000)
        page.locator('#f25-w5').fill('1');page.locator('#f25-w2').fill('1');page.locator('#f25-wprefix').fill('AP');page.get_by_role('button',name='批量建立 WiFi',exact=True).click();expect(page.get_by_role('status')).to_contain_text('WiFi 配置已保存',timeout=10000);expect(page.locator('#f25-wifis .wifirow')).to_have_count(2)
        page.locator('#f25-search').fill('手机 B');expect(page.locator('#f25-devices .device')).to_have_count(1);page.locator('#f25-search').fill('')
        page.screenshot(path=str(pathlib.Path(__file__).parents[1]/'test-results/ui-desktop-dev2.png'),full_page=True)
        page.set_viewport_size({'width':390,'height':844});expect(page.get_by_text('DNS 设置',exact=True)).to_be_visible();page.screenshot(path=str(pathlib.Path(__file__).parents[1]/'test-results/ui-mobile-dev2.png'),full_page=True)
        assert not errors,errors
        browser.close();print('dev.2 responsive devices, DNS, import and multi-WiFi UI passed')
finally:server.shutdown();server.server_close()
