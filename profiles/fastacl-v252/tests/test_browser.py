"""Exercise the responsive FastACL 2.5.2 Lite UI against an isolated demo backend."""
import pathlib, re, threading
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
        expect(page.get_by_text('FastACL 2.5.2 Lite',exact=False)).to_be_visible()
        expect(page.locator('#f25-devices .device')).to_have_count(3)
        expect(page.get_by_text('附加 WiFi',exact=True)).to_be_visible()
        expect(page.locator('#f25-direct-dns')).to_have_value('alidns');expect(page.locator('#f25-proxy-dns')).to_have_value('cloudflare')

        # Global DNS is a synchronous application-layer hot apply.
        page.locator('#f25-proxy-dns').select_option('google');page.get_by_role('button',name='保存 DNS',exact=True).click()
        expect(page.get_by_role('status')).to_contain_text('应用层快速切换完成',timeout=10000)

        # Assign a node directly from the node list to a main-WiFi client.
        page.locator('#f25-node-list .node').first.get_by_role('button',name='快速分配').click()
        expect(page.get_by_text('快速分配节点',exact=True)).to_be_visible()
        page.locator('#f25-assign-type').select_option('device')
        page.locator('#f25-assign-target').select_option('02:00:00:00:00:02')
        page.locator('#f25-assign-go').click()
        expect(page.get_by_role('status')).to_contain_text('应用层快速切换完成',timeout=10000)
        expect(page.locator('#f25-assign-modal')).to_have_class(re.compile(r'\bhidden\b'))

        # Import remains available but is collapsed by default in Lite.
        page.get_by_role('button',name='+ 导入节点',exact=True).click()
        page.locator('#f25-links').fill('socks5://user:pass@proxy.example:1080#US\nproxy2.example:1080:user:pass')
        page.get_by_role('button',name='导入',exact=True).click();expect(page.get_by_role('status')).to_contain_text('成功导入 2 个节点',timeout=10000)

        # Creating WiFi is intentionally the cold topology path.
        page.locator('#f25-w5').fill('1');page.locator('#f25-w2').fill('1');page.locator('#f25-wprefix').fill('AP')
        page.get_by_role('button',name='批量建立 WiFi',exact=True).click();expect(page.get_by_role('status')).to_contain_text('WiFi 拓扑已保存',timeout=10000)
        expect(page.locator('#f25-wifis .wifirow')).to_have_count(2)

        # Existing WiFi node change goes back to the hot path.
        page.locator('#f25-node-list .node').nth(1).get_by_role('button',name='快速分配').click()
        page.locator('#f25-assign-type').select_option('wifi')
        page.locator('#f25-assign-target').select_option('jfa25w01')
        page.locator('#f25-assign-go').click()
        expect(page.get_by_role('status')).to_contain_text('应用层快速切换',timeout=10000)

        # Batch delete accepts the dialog, deletes unused nodes and skips bound ones.
        page.locator('#f25-select-all').click()
        page.once('dialog',lambda d:d.accept())
        page.locator('#f25-delete-selected').click()
        expect(page.get_by_role('status')).to_contain_text('跳过',timeout=10000)

        page.locator('#f25-search').fill('手机 B');expect(page.locator('#f25-devices .device')).to_have_count(1);page.locator('#f25-search').fill('')
        page.screenshot(path=str(pathlib.Path(__file__).parents[1]/'test-results/ui-desktop-lite.png'),full_page=True)
        page.set_viewport_size({'width':390,'height':844});expect(page.get_by_text('全局 DNS',exact=True)).to_be_visible();page.screenshot(path=str(pathlib.Path(__file__).parents[1]/'test-results/ui-mobile-lite.png'),full_page=True)
        assert not errors,errors
        browser.close();print('FastACL 2.5.2 Lite quick-switch, batch-delete and responsive UI passed')
finally:server.shutdown();server.server_close()
