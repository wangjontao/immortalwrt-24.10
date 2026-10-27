"""Local demo backend for the FastACL 2.5.6 LuCI UI; no router access."""
import json, math, pathlib, re, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

ROOT=pathlib.Path(__file__).resolve().parents[1]
VERSION=re.search(r'^PKG_VERSION:=(.+)$',(ROOT/'package-Makefile').read_text(),re.M).group(1)
PREVIEW_ORIGIN=time.monotonic()
CATALOG=[
 {'id':'dns360','label':'360 安全 DNS','scope':'direct','kind':'doh'},
 {'id':'public114','label':'114 公共 DNS','scope':'direct','kind':'udp'},
 {'id':'cnnic','label':'CNNIC SDNS','scope':'direct','kind':'udp'},
 {'id':'baidu','label':'百度 DNS','scope':'direct','kind':'udp','ip':'180.76.76.76','name':''},
 {'id':'alidns','label':'阿里 DNS','scope':'direct','kind':'doh','ip':'223.5.5.5','name':'dns.alidns.com'},
 {'id':'tencent','label':'腾讯 DNSPod','scope':'direct','kind':'doh','ip':'1.12.12.12','name':'doh.pub'},
 {'id':'cloudflare','label':'Cloudflare','scope':'proxy','kind':'doh','ip':'1.1.1.1','name':'cloudflare-dns.com'},
 {'id':'google','label':'Google','scope':'proxy','kind':'doh','ip':'8.8.8.8','name':'dns.google'},
 {'id':'opendns','label':'Cisco OpenDNS','scope':'proxy','kind':'doh','ip':'208.67.222.222','name':'doh.opendns.com'},
 {'id':'quad9','label':'Quad9','scope':'proxy','kind':'doh','ip':'9.9.9.9','name':'dns.quad9.net'},
]

PREVIEW_CSS=r"""
:root{--shell-ink:#27364d;--shell-muted:#77859a;--shell-line:#d7e2ee;--shell-active:#e5f0fb}
html,body{margin:0;min-height:100%;background:#eef3f8;color:var(--shell-ink)}
body,button,input,select,textarea{font-family:system-ui,-apple-system,'Segoe UI',sans-serif}
.preview-shell{display:grid;grid-template-columns:248px minmax(0,1fr);min-height:100vh}
.preview-sidebar{position:sticky;top:0;height:100vh;min-width:0;box-sizing:border-box;display:flex;flex-direction:column;padding:18px 12px;overflow:hidden;background:#fff;border-right:1px solid #e7edf4;box-shadow:8px 0 30px rgba(49,79,116,.04)}
.preview-brand{display:flex;flex-direction:column;justify-content:center;box-sizing:border-box;width:188px;min-height:92px;margin:0 auto 18px;padding:13px 14px;border:1px solid rgba(255,255,255,.62);border-radius:10px;color:#fff;background:linear-gradient(132deg,#1769e0 0%,#2497ea 45%,#2cbdb3 72%,#7b79e8 100%);box-shadow:inset 0 1px 0 rgba(255,255,255,.38),0 7px 18px rgba(31,91,166,.2)}
.preview-brand b{display:block;text-align:center;font-size:24px;line-height:1.2}.preview-brand small{display:block;margin-top:6px;text-align:center;color:#fff;font-size:22px;line-height:1.25}
.preview-nav{display:flex;flex-direction:column;gap:3px;min-width:0;max-width:100%}.preview-nav a,.preview-nav-heading,.preview-nav-group{display:flex;align-items:center;min-width:0;min-height:38px;box-sizing:border-box;padding:0 13px;border:1px solid transparent;border-radius:7px;color:#51637b;text-decoration:none;font-size:14px;font-weight:600}
.preview-nav-heading{margin-bottom:6px;min-height:48px;color:#fff;background:linear-gradient(105deg,#4d55df,#4d50e4);box-shadow:0 5px 12px rgba(68,72,210,.16);font-weight:750}
.preview-nav-group{margin-top:7px;color:#5d6a7d;font-weight:700}.preview-nav-group span,.preview-nav-heading span{margin-left:auto;font-size:18px;line-height:1}
.preview-nav-sub{padding-left:34px!important}.preview-nav-sub.active{border-color:#d9e3ef!important;border-left:3px solid #4c5be3!important;background:#fff!important;color:#3e4c62!important;box-shadow:0 2px 7px rgba(45,72,109,.04)!important}
.preview-nav a:hover{background:#eef5fc;border-color:#dce8f4}
.preview-sidefoot{margin-top:auto;padding:15px 10px 0;border-top:1px solid #e1e9f2;color:var(--shell-muted);font-size:11px;line-height:1.7}
.preview-main{min-width:0;max-width:100%;overflow:hidden;padding:24px 28px 34px}.preview-topbar{display:flex;align-items:center;justify-content:space-between;gap:16px;max-width:1500px;margin:0 auto 16px;color:#607089;font-size:12px}
.preview-topbar b{color:#304a69}.preview-badge{padding:6px 10px;border:1px solid #c9ddec;border-radius:999px;background:#f7fbff;color:#426485;white-space:nowrap}
.preview-content{min-width:0;max-width:min(1500px,100%);margin:0 auto}
@media(max-width:860px){.preview-shell{grid-template-columns:minmax(0,1fr)}.preview-sidebar{position:sticky;z-index:100;height:auto;padding:10px 12px;border-right:0;border-bottom:1px solid var(--shell-line)}.preview-brand{width:auto;min-height:0;margin:0 0 8px;padding:6px 12px}.preview-brand b{font-size:15px;text-align:left}.preview-brand small{display:inline;margin:0 0 0 8px;font-size:15px}.preview-nav{width:100%;flex-direction:row;overflow-x:auto;padding-bottom:2px}.preview-nav>*{flex:0 0 auto}.preview-nav a,.preview-nav-heading,.preview-nav-group{min-height:34px;margin:0;padding:0 10px!important;white-space:nowrap;font-size:13px}.preview-nav-sub{border-left:0!important}.preview-nav-group span,.preview-nav-heading span{display:none}.preview-sidefoot{display:none}.preview-main{padding:18px 14px 28px}.preview-topbar{margin-bottom:12px}}
@media(max-width:520px){.preview-sidebar{padding:10px 10px 8px}.preview-brand{padding-bottom:8px}.preview-nav{gap:5px}.preview-nav a{min-height:34px;padding:0 10px}.preview-main{padding:14px 9px 24px}.preview-badge{font-size:10px;padding:5px 8px}}
"""

def preview_shell(content,title,active):
    items=[
        ('/center','监测中心','center'),
        ('/wireless','无线设备','wireless'),
        ('/','FastACL 控制台','console'),
        ('/center','BBR TCP 加速','bbr'),
        ('/center','在线升级','upgrade'),
    ]
    subnav=''.join(
        '<a class="preview-nav-sub %s" href="%s">%s</a>' % ('active' if key==active else '',href,label)
        for href,label,key in items
    )
    nav='<div class="preview-nav-heading"><span style="margin:0">JuLiang 控制面板</span><span>⌄</span></div>'+subnav
    nav+='<div class="preview-nav-group">状态 <span>›</span></div>'
    nav+='<div class="preview-nav-group">系统 <span>›</span></div>'
    nav+='<div class="preview-nav-group">网络 <span>›</span></div>'
    nav+='<a class="preview-nav-group" href="#">退出</a>'
    head=(
        '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>%s · JuLiang OS 2.6.7</title><style>%s</style></head><body>'
        '<div class="preview-shell"><aside class="preview-sidebar">'
        '<div class="preview-brand"><b>JuLiang</b><small>网络服务</small></div>'
        '<nav class="preview-nav">%s</nav><div class="preview-sidefoot">'
        'dae / eBPF 数据面<br>本地界面效果预览</div></aside>'
        '<main class="preview-main"><header class="preview-topbar">'
        '<div>JuLiang <b>/ %s</b></div><span class="preview-badge">2.6.7 · 本地预览</span>'
        '</header><div class="preview-content">'
    ) % (title, PREVIEW_CSS, nav, title)
    return head+content+'</div></main></div></body></html>'

def render_preview(path,title,active):
    text=(ROOT/path).read_text(encoding='utf-8')
    urls={
        'admin/juliang/status':'/cgi-bin/luci/admin/juliang/status',
        'admin/juliang/wireless':'/wireless',
        'admin/juliang/fastacl':'/',
        'admin/services':'/cgi-bin/luci/admin/services',
        'admin/services/fastacl252_wireless':'/cgi-bin/luci/admin/services/fastacl252_wireless',
    }
    def build_url(match):
        args=[a or b for a,b in re.findall(r"'([^']*)'|\"([^\"]*)\"",match.group(1))]
        return urls.get('/'.join(args),'#')
    text=re.sub(r'<%=luci\.dispatcher\.build_url\((.*?)\)%>',build_url,text,flags=re.S)
    text=text.replace('<%=token%>','demo-token')
    text=re.sub(r'<%.*?%>','',text,flags=re.S)
    return preview_shell(text,title,active)
state={'ok':True,'version':VERSION+' · 本地演示','enabled':True,'direct_dns':'alidns','proxy_dns':'cloudflare','dns_catalog':CATALOG,
 'network':'lan','router_ip':'192.168.7.1','runtime':{'engine':'running','firewall':True,'backend':'nft','switch':'hot','request':'hot'},'job':'0','apply_log':'','subscription_running':False,
 'wan_up':True,'wan_ip':'100.64.0.2','wan_device':'pppoe-wan','wifi_count':18,'managed_wifi':3,'uptime':93784,
 'fastacl':{'engine':'running'},
 'ports':[{'device':'wan','known':True,'connected':True,'speed':2500},{'device':'lan1','known':True,'connected':True,'speed':1000},{'device':'lan2','known':True,'connected':False,'speed':1000}],
 'traffic':{'rx_bytes':0,'tx_bytes':0,'timestamp':0,'device':'pppoe-wan'},
 'traffic_totals':{'available':True,'device':'pppoe-wan','today_rx':0,'today_tx':0,'month_rx':0,'month_tx':0,'total_rx':0,'total_tx':0},
 'nodes':[{'id':'us','name':'美国出口 A','protocol':'socks'},{'id':'jp','name':'日本出口 B','protocol':'http'},{'id':'front','name':'前置节点','protocol':'vless'}],
 'subscriptions':[],
 'devices':[{'mac':'02:00:00:00:00:01','name':'手机 A','ip':'192.168.7.101','fixed_ip':'192.168.7.101','bound':True,'online':True,'mode':'proxy','node':'us','preproxy':'','dns':'inherit'},
            {'mac':'02:00:00:00:00:02','name':'手机 B','ip':'192.168.7.102','bound':False,'online':True,'mode':'direct','dns':'inherit'},
            {'mac':'02:00:00:00:00:03','name':'电脑 C','ip':'192.168.7.103','bound':True,'online':False,'mode':'direct','dns':'alidns'}],
 'wifi':{'radios':{'5g':['radio1'],'2g':['radio0']},'managed':[],'main':{'mode':'direct','node':'','preproxy':'','dns':'inherit','split_mode':'all','split_rules':'','platforms':'','dns_split':'0','block_domains':''},'counts':{'5g':0,'2g':0},'max5':14,'max2':8}}


def bound_nodes():
    out=set()
    for d in state['devices']:
        if d.get('bound'):
            if d.get('node'):out.add(d['node'])
            if d.get('preproxy'):out.add(d['preproxy'])
    for w in state['wifi']['managed']:
        if w.get('node'):out.add(w['node'])
        if w.get('preproxy'):out.add(w['preproxy'])
    return out


def clear_node_binding(nid):
    for rows in (state['devices'],state['wifi']['managed']):
        for row in rows:
            if row.get('node')==nid:row['node']=''
            if row.get('preproxy')==nid:row['preproxy']=''


class Handler(BaseHTTPRequestHandler):
    def reply(self,data):
        b=json.dumps(data,ensure_ascii=False).encode();self.send_response(200);self.send_header('Content-Type','application/json; charset=utf-8');self.end_headers();self.wfile.write(b)
    def do_GET(self):
        now=time.monotonic()
        elapsed=now-PREVIEW_ORIGIN
        gib=1024**3
        mib=1024**2
        state['uptime']=93784+int(elapsed)
        state['traffic']={
            'rx_bytes':int(145*gib+elapsed*6.8*mib+math.sin(elapsed*1.4)*3*mib),
            'tx_bytes':int(38*gib+elapsed*1.1*mib+math.sin(elapsed*1.8+0.8)*0.5*mib),
            'timestamp':now,
            'device':'pppoe-wan',
        }
        state['traffic_totals']={
            'available':True,
            'device':'pppoe-wan',
            'today_rx':int(86.42*gib),
            'today_tx':int(12.84*gib),
            'month_rx':int(1.86*1024*gib),
            'month_tx':int(328.7*gib),
            'total_rx':int(4.92*1024*gib),
            'total_tx':int(728.4*gib),
        }
        if self.path.endswith('/juliang/status'):
            self.reply(state);return
        if self.path.endswith('/fastacl252_node_export'):
            self.reply({'ok':True,'count':len(state['nodes']),'text':'\n'.join('socks5://demo@'+n['id']+'.example:1080#'+n['name'] for n in state['nodes'])});return
        if self.path.endswith('/fastacl252_wireless'):
            t=time.monotonic();self.reply({'ok':True,'timestamp':t,'interfaces':[{'id':'phy1-ap0','ssid':'JuLiangTK','radio':'radio1','network':'lan','up':True,'stations':[{'mac':'02:00:00:00:00:01','name':'手机 A','ip':'192.168.7.101','signal':-51,'rx_bytes':int(t*100000),'tx_bytes':int(t*300000),'tx_link_mbps':866.7,'rx_link_mbps':780}]}]});return
        if self.path.endswith('/fastacl252_status'):self.reply(state);return
        routes={
            '/':('root/usr/lib/lua/luci/view/fastacl252/console.htm','FastACL 控制台','console'),
            '/index.html':('root/usr/lib/lua/luci/view/fastacl252/console.htm','FastACL 控制台','console'),
            '/center':('root/usr/lib/lua/luci/view/juliang_center/home.htm','监测中心','center'),
            '/wireless':('root/usr/lib/lua/luci/view/juliang_center/wireless.htm','无线设备','wireless'),
        }
        if self.path not in routes:self.send_error(404);return
        path,title,active=routes[self.path]
        text=render_preview(path,title,active)
        self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.end_headers();self.wfile.write(text.encode())
    def do_POST(self):
        form=parse_qs(self.rfile.read(int(self.headers.get('Content-Length',0))).decode())
        if self.path.endswith('/fastacl252_rename_node'):
            node=next(n for n in state['nodes'] if n['id']==form['id'][0]);node['name']=form['name'][0]
            self.reply({'ok':True});return
        if self.path.endswith('/fastacl252_device_name'):
            row=next(r for r in state['devices'] if r['mac']==form['mac'][0]);name=form.get('name',[''])[0];row['name']=name;row['custom_name']=name
            self.reply({'ok':True,'name':name});return
        if self.path.endswith('/fastacl252_node_detail'):
            node=next(n for n in state['nodes'] if n['id']==form['id'][0])
            outbound=node.get('outbound',{'type':node['protocol'],'server':'proxy.example','server_port':1080})
            self.reply({'ok':True,'name':node['name'],'protocol':node['protocol'],'outbound':outbound,'link':f"socks5://demo@{node['id']}.example:1080#"+node['name']});return
        if self.path.endswith('/fastacl252_update_node'):
            data=json.loads(form['data'][0]);node=next(n for n in state['nodes'] if n['id']==data['id']);node['name']=data.get('name',node['name']);node['outbound']=data.get('outbound',{});self.reply({'ok':True,'message':'节点参数已保存并应用'});return
        if self.path.endswith('/fastacl252_probe'):
            self.reply({'ok':True,'ip':'203.0.113.9','country':'JP','elapsed_ms':123,'proxy':True,'note':'绑定出口检测，非手机实机检测'});return
        if self.path.endswith('/fastacl252_save'):
            data=json.loads(form['data'][0]);state['direct_dns']=data.get('direct_dns',state['direct_dns']);state['proxy_dns']=data.get('proxy_dns',state['proxy_dns'])
            for d in data.get('devices',[]):
                r=next(r for r in state['devices'] if r['mac']==d['mac'])
                if d.get('remove'):r.update(bound=False,mode='direct',node='',preproxy='',dns='inherit')
                else:r.update(d,bound=True,fixed_ip=d['ip'],mode='proxy' if d.get('node') else 'direct')
            state['runtime']['switch']='hot';state['runtime']['request']='hot'
            self.reply({'ok':True,'message':'应用层快速切换完成；未重载 network / WiFi / firewall。'});return
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
                state['runtime']['switch']='app-restart';state['runtime']['request']='cold';msg='WiFi 拓扑已保存并重新加载。'
            elif a=='update':
                r=next(r for r in info['managed'] if r['id']==data['id']);r.update(data,mode='proxy' if data.get('node') else 'direct')
                state['runtime']['switch']='hot';state['runtime']['request']='hot';msg='节点已应用层快速切换；network / WiFi / firewall 均未重载。'
            elif a=='remove':
                r=next(r for r in info['managed'] if r['id']==data['id']);info['counts'][r['band']]-=1;info['managed'].remove(r);msg='WiFi 拓扑已保存并重新加载。'
            elif a=='hide_all':msg='SSID 显示状态已更新；未重载 network / firewall / dae。'
            elif a=='lan_update':
                info['main']={'mode':'proxy' if data.get('node') else 'direct','node':data.get('node',''),'preproxy':data.get('preproxy',''),'dns':data.get('dns','inherit'),'split_mode':data.get('split_mode','all'),'split_rules':data.get('split_rules',''),'platforms':data.get('platforms',''),'dns_split':data.get('dns_split','0'),'block_domains':data.get('block_domains','')}
                state['runtime']['switch']='hot';state['runtime']['request']='hot';msg='主 WiFi / 有线 LAN 默认出口已更新。'
            else:self.reply({'ok':False,'error':'bad action'});return
            self.reply({'ok':True,'message':msg});return
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
        if self.path.endswith('/fastacl252_delete_nodes'):
            data=json.loads(form['data'][0]);ids=data.get('ids',[]);force=data.get('force') in (True,1,'1');bound=bound_nodes();deleted=[];skipped=[]
            for nid in ids:
                if nid in bound and not force:skipped.append({'id':nid,'reason':'正在使用'})
                elif any(n['id']==nid for n in state['nodes']):deleted.append(nid)
                else:skipped.append({'id':nid,'reason':'节点不存在'})
            for nid in deleted:clear_node_binding(nid)
            state['nodes']=[n for n in state['nodes'] if n['id'] not in deleted]
            message=f'已删除 {len(deleted)} 个节点；跳过 {len(skipped)} 个无效节点。'
            if force:message+=' 关联设备和 WiFi 已切换为国内直连。'
            self.reply({'ok':True,'deleted':deleted,'skipped':skipped,'forced':force,'message':message});return
        if self.path.endswith('/fastacl252_delete_node'):
            nid=form.get('id',[''])[0];force=form.get('force',[''])[0] in ('1','true')
            if nid in bound_nodes() and not force:self.reply({'ok':False,'error':'节点仍在使用'});return
            clear_node_binding(nid)
            state['nodes']=[n for n in state['nodes'] if n['id']!=nid];self.reply({'ok':True});return
        self.send_error(404)
    def log_message(self,*args):pass

if __name__=='__main__':ThreadingHTTPServer(('127.0.0.1',8525),Handler).serve_forever()
