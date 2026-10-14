"""Local demo backend for the FastACL dev.2 LuCI UI; no router access."""
import json, pathlib, re, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

ROOT=pathlib.Path(__file__).resolve().parents[1]
CATALOG=[
 {'id':'baidu','label':'百度 DNS','scope':'direct','kind':'udp','ip':'180.76.76.76','name':''},
 {'id':'alidns','label':'阿里 DNS','scope':'direct','kind':'doh','ip':'223.5.5.5','name':'dns.alidns.com'},
 {'id':'tencent','label':'腾讯 DNSPod','scope':'direct','kind':'doh','ip':'1.12.12.12','name':'doh.pub'},
 {'id':'cloudflare','label':'Cloudflare','scope':'proxy','kind':'doh','ip':'1.1.1.1','name':'cloudflare-dns.com'},
 {'id':'google','label':'Google','scope':'proxy','kind':'doh','ip':'8.8.8.8','name':'dns.google'},
 {'id':'opendns','label':'Cisco OpenDNS','scope':'proxy','kind':'doh','ip':'208.67.222.222','name':'doh.opendns.com'},
 {'id':'quad9','label':'Quad9','scope':'proxy','kind':'doh','ip':'9.9.9.9','name':'dns.quad9.net'},
]
state={'ok':True,'version':'2.5.2-dev.2 · 本地演示','enabled':True,'direct_dns':'alidns','proxy_dns':'cloudflare','dns_catalog':CATALOG,
 'network':'lan','router_ip':'192.168.7.1','runtime':{'engine':'running','firewall':True,'backend':'nft'},'job':'0','subscription_running':False,
 'nodes':[{'id':'us','name':'美国出口 A','protocol':'socks'},{'id':'jp','name':'日本出口 B','protocol':'http'},{'id':'front','name':'前置节点','protocol':'vless'}],
 'subscriptions':[],
 'devices':[{'mac':'02:00:00:00:00:01','name':'手机 A','ip':'192.168.7.101','fixed_ip':'192.168.7.101','bound':True,'online':True,'mode':'proxy','node':'us','preproxy':'','dns':'inherit'},
            {'mac':'02:00:00:00:00:02','name':'手机 B','ip':'192.168.7.102','bound':False,'online':True,'mode':'direct','dns':'inherit'},
            {'mac':'02:00:00:00:00:03','name':'电脑 C','ip':'192.168.7.103','bound':True,'online':False,'mode':'direct','dns':'alidns'}],
 'wifi':{'radios':{'5g':['radio1'],'2g':['radio0']},'managed':[],'counts':{'5g':0,'2g':0},'max5':14,'max2':8}}

class Handler(BaseHTTPRequestHandler):
    def reply(self,data):
        b=json.dumps(data,ensure_ascii=False).encode();self.send_response(200);self.send_header('Content-Type','application/json; charset=utf-8');self.end_headers();self.wfile.write(b)
    def do_GET(self):
        if self.path.endswith('/fastacl252_status'):self.reply(state);return
        if self.path not in ('/','/index.html'):self.send_error(404);return
        text=(ROOT/'root/usr/lib/lua/luci/view/fastacl252/console.htm').read_text(encoding='utf-8')
        text=text.replace('<%+header%>','<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FastACL dev.2 演示</title><style>body{font:15px system-ui;background:#f4f6fa;color:#242b40;padding:24px}button{padding:8px 14px;border:1px solid #bbc4db;border-radius:6px;background:#fff}.cbi-button-apply,.cbi-button-add{background:#5263d9;color:white}input,select,textarea{padding:8px;border:1px solid #cbd1df;border-radius:6px}h3{margin-top:0}</style>')
        text=text.replace('<%+footer%>','</html>')
        text=re.sub(r'<%=luci.dispatcher.build_url\("admin","services"\)%>','/cgi-bin/luci/admin/services',text).replace('<%=token%>','demo-token')
        self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.end_headers();self.wfile.write(text.encode())
    def do_POST(self):
        form=parse_qs(self.rfile.read(int(self.headers.get('Content-Length',0))).decode())
        if self.path.endswith('/fastacl252_save'):
            data=json.loads(form['data'][0]);state['direct_dns']=data.get('direct_dns',state['direct_dns']);state['proxy_dns']=data.get('proxy_dns',state['proxy_dns'])
            for d in data.get('devices',[]):
                r=next(r for r in state['devices'] if r['mac']==d['mac'])
                if d.get('remove'):r.update(bound=False,mode='direct',node='',preproxy='',dns='inherit')
                else:r.update(d,bound=True,fixed_ip=d['ip'],mode='proxy' if d.get('node') else 'direct')
            self.reply({'ok':True,'message':'演示配置已保存'});return
        if self.path.endswith('/fastacl252_import'):
            lines=[x for x in form.get('links',[''])[0].splitlines() if x.strip()]
            for i,line in enumerate(lines,1):state['nodes'].append({'id':'manual'+str(len(state['nodes'])+1),'name':'手工节点 '+str(i),'protocol':'socks'})
            self.reply({'ok':True,'count':len(lines)});return
        if self.path.endswith('/fastacl252_wifi'):
            data=json.loads(form['data'][0]);a=data['action'];info=state['wifi']
            if a=='create':
                seq=len(info['managed'])+1
                for band,count in [('5g',int(data.get('count5',0))),('2g',int(data.get('count2',0)))]:
                    for _ in range(count):
                        idx=seq;seq+=1;ssid=str(data.get('prefix','A'))+str(int(data.get('start',1))+idx-1);net='jfa25w%02d'%idx;sub='172.16.%d.0/24'%idx
                        row={'id':net,'network':net,'ssid':ssid,'band':band,'subnet':sub,'mode':'proxy' if data.get('node') else 'direct','node':data.get('node',''),'preproxy':data.get('preproxy',''),'dns':data.get('dns','inherit'),'dns_type':data.get('dns_type',''),'dns_ip':data.get('dns_ip',''),'dns_name':data.get('dns_name','')}
                        info['managed'].append(row);info['counts'][band]+=1
            elif a=='update':
                r=next(r for r in info['managed'] if r['id']==data['id']);r.update(data,mode='proxy' if data.get('node') else 'direct')
            elif a=='remove':
                r=next(r for r in info['managed'] if r['id']==data['id']);info['counts'][r['band']]-=1;info['managed'].remove(r)
            self.reply({'ok':True,'message':'WiFi 配置已保存并重新加载'});return
        if self.path.endswith('/fastacl252_subscription'):
            data=json.loads(form['data'][0]);action=data['action']
            if action=='save':state['subscriptions'].append(dict(id='airport1',name=data['name'],interval_hours=data['interval_hours'],enabled=data['enabled'],status={}))
            elif action=='update':
                state['subscription_running']=True
                def done():
                    if state['subscriptions']:
                        state['nodes'].append(dict(id='airportnode',name='机场美国出口',protocol='socks',owner='airport1'));state['subscriptions'][0]['status']=dict(ok=True,count=1,attempt=int(time.time()))
                    state['subscription_running']=False
                threading.Timer(0.2,done).start()
            elif action=='remove':state['subscriptions']=[]
            self.reply({'ok':True});return
        if self.path.endswith('/fastacl252_delete_node'):
            nid=form.get('id',[''])[0];state['nodes']=[n for n in state['nodes'] if n['id']!=nid];self.reply({'ok':True});return
        self.send_error(404)
    def log_message(self,*args):pass

if __name__=='__main__':ThreadingHTTPServer(('127.0.0.1',8525),Handler).serve_forever()
