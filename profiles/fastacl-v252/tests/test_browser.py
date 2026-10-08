"""Exercise the real UI against an isolated, in-memory demo backend."""
import copy, pathlib, threading
from http.server import ThreadingHTTPServer
from playwright.sync_api import sync_playwright, expect
import preview_server

server=ThreadingHTTPServer(('127.0.0.1',0),preview_server.Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
url=f'http://127.0.0.1:{server.server_port}'
try:
    with sync_playwright() as p:
        browser=p.chromium.launch(); page=browser.new_page(viewport={'width':1440,'height':1080}); errors=[]
        page.on('pageerror',lambda e:errors.append(str(e)))
        page.goto(url); expect(page.locator('#f25-rows tr')).to_have_count(3)
        row=page.locator('#f25-rows tr').filter(has=page.locator('td',has_text='02:00:00:00:00:02'))
        row.locator('select').nth(0).select_option('jp'); row.get_by_role('button',name='保存',exact=True).click()
        expect(page.get_by_role('status')).to_contain_text('配置已应用',timeout=10000)
        page.reload(); expect(page.locator('#f25-rows tr')).to_have_count(3)
        row=page.locator('#f25-rows tr').filter(has=page.locator('td',has_text='02:00:00:00:00:02'))
        expect(row.locator('select').nth(0)).to_have_value('jp')
        page.locator('#f25-dns').select_option('private'); page.get_by_role('button',name='保存 DNS',exact=True).click()
        expect(page.get_by_role('status')).to_contain_text('配置已应用',timeout=10000)
        page.reload(); expect(page.locator('#f25-dns')).to_have_value('private')
        page.locator('#f25-search').fill('手机 B'); expect(page.locator('#f25-rows tr')).to_have_count(1)
        page.locator('#f25-search').fill(''); expect(page.locator('#f25-rows tr')).to_have_count(3)
        page.get_by_text('节点管理与机场订阅',exact=True).click(); expect(page.locator('#f25-sub-url')).to_be_visible()
        page.locator('#f25-sub-name').fill('测试机场'); page.locator('#f25-sub-url').fill('https://airport.example/sub?token=demo')
        page.get_by_role('button',name='添加订阅',exact=True).click(); expect(page.locator('#f25-sub-list')).to_contain_text('测试机场')
        page.get_by_role('button',name='更新全部订阅',exact=True).click(); expect(page.get_by_role('status')).to_contain_text('订阅更新完成',timeout=10000)
        expect(page.locator('#f25-node-list')).to_contain_text('机场美国出口')
        assert not page.get_by_text('无线分配',exact=True).count()
        assert not page.get_by_text('批量建立无线',exact=True).count()
        page.screenshot(path=str(pathlib.Path(__file__).parents[1]/'test-results/ui-desktop.png'),full_page=True)
        page.set_viewport_size({'width':390,'height':844}); page.screenshot(path=str(pathlib.Path(__file__).parents[1]/'test-results/ui-mobile.png'),full_page=True)
        assert not errors,errors
        browser.close(); print('Device assignment, DNS persistence, search, subscription panel and no old WiFi menus passed')
finally:server.shutdown();server.server_close()
