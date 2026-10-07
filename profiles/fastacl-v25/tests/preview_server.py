"""Local demo backend, with in-memory devices only; no router access."""
import json, pathlib, re, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

ROOT=pathlib.Path(__file__).resolve().parents[1]
state={'ok':True,'version':'2.5.0-dev.1 · 本地演示','enabled':True,'dns_policy':'direct','network':'lan','router_ip':'192.168.7.1','runtime':{'engine':'running','firewall':True,'backend':'nft'},'job':'0','nodes':[{'id':'us','name':'美国出口 A','protocol':'socks'},{'id':'jp','name':'日本出口 B','protocol':'http'},{'id':'front','name':'前置节点','protocol':'vless'}],'devices':[{'mac':'02:00:00:00:00:01','name':'手机 A','ip':'192.168.7.101','fixed_ip':'192.168.7.101','bound':True,'online':True,'mode':'proxy','node':'us','preproxy':''},{'mac':'02:00:00:00:00:02','name':'手机 B','ip':'192.168.7.102','bound':False,'online':True,'mode':'direct'},{'mac':'02:00:00:00:00:03','name':'电脑 C','ip':'192.168.7.103','bound':True,'online':False,'mode':'direct'}]}

class Handler(BaseHTTPRequestHandler):
    def reply(self,data):
        b=json.dumps(data,ensure_ascii=False).encode(); self.send_response(200); self.send_header('Content-Type','application/json; charset=utf-8'); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.endswith('/fastacl25_status'): self.reply(state); return
        if self.path not in ('/','/index.html'): self.send_error(404); return
        text=(ROOT/'root/usr/lib/lua/luci/view/fastacl25/console.htm').read_text(encoding='utf-8')
        if '<%+juliangtk/header%>' in text:
            header=(ROOT/'root/usr/lib/lua/luci/view/juliangtk/header.htm').read_text(encoding='utf-8')
            header=re.sub(r'<%=luci.dispatcher.build_url\((.*?)\)%>',lambda m:'/cgi-bin/luci/'+m[1].replace("'",'').replace(',','/'),header)
            css=(ROOT/'root/www/luci-static/juliangtk/console.css').read_text(encoding='utf-8')
            header=header.replace('<link rel="stylesheet" href="/luci-static/juliangtk/console.css">','<style>'+css+'</style>')
            text=text.replace('<%+juliangtk/header%>',header).replace('<%+juliangtk/footer%>','</main></body></html>')
        text=text.replace('<%+header%>','<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FastACL 2.5 本地演示</title><style>body{font:15px system-ui;background:#f4f6fa;color:#242b40;padding:24px}button{padding:8px 14px;border:1px solid #bbc4db;border-radius:6px;background:#fff}.cbi-button-apply{background:#5263d9;color:white}input,select,textarea{padding:8px;border:1px solid #cbd1df;border-radius:6px}h3{margin-top:0}</style>')
        text=text.replace('<%+footer%>','</html>')
        text=re.sub(r'<%=luci.dispatcher.build_url\("admin","services"\)%>','/cgi-bin/luci/admin/services',text).replace('<%=token%>','demo-token')
        self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8'); self.end_headers(); self.wfile.write(text.encode())
    def do_POST(self):
        form=parse_qs(self.rfile.read(int(self.headers.get('Content-Length',0))).decode())
        if self.path.endswith('/fastacl25_save'):
            data=json.loads(form['data'][0]); state['dns_policy']=data.get('dns_policy',state['dns_policy'])
            for d in data.get('devices',[]):
                r=next(r for r in state['devices'] if r['mac']==d['mac'])
                if d.get('remove'): r.update(bound=False,mode='direct',node='',preproxy='')
                else: r.update(d,bound=True,fixed_ip=d['ip'])
            self.reply({'ok':True,'message':'演示配置已保存'}); return
        if self.path.endswith('/fastacl25_import'): self.reply({'ok':True}); return
        if self.path.endswith('/fastacl25_subscription'):
            data=json.loads(form['data'][0]); action=data['action']
            if action=='save':
                state.setdefault('subscriptions',[]).append(dict(id='airport1',name=data['name'],interval_hours=data['interval_hours'],enabled=data['enabled'],status={}))
            elif action=='update':
                state['subscription_running']=True
                def done():
                    state['nodes'].append(dict(id='airportnode',name='机场美国出口',protocol='socks',owner='airport1'))
                    state['subscriptions'][0]['status']=dict(ok=True,count=1,attempt=int(time.time()))
                    state['subscription_running']=False
                threading.Timer(0.2,done).start()
            elif action=='remove':state['subscriptions']=[]
            self.reply({'ok':True}); return
        self.send_error(404)
    def log_message(self,*args): pass

if __name__=='__main__': ThreadingHTTPServer(('127.0.0.1',8525),Handler).serve_forever()
