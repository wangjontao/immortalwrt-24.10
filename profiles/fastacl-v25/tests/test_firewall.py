"""Privileged Linux-only packet tests in temporary network namespaces."""
import contextlib, json, os, pathlib, socket, socketserver, struct, subprocess, sys, tempfile, threading, time
from test_policy import config, compile, from_lua, policy, to_lua

def proxy_server():
    class Handler(socketserver.BaseRequestHandler):
        def exact(self,n):
            b=b''
            while len(b)<n:
                d=self.request.recv(n-len(b))
                if not d: raise EOFError()
                b+=d
            return b
        def headers(self,initial=b''):
            b=initial
            while b'\r\n\r\n' not in b:
                d=self.request.recv(4096)
                if not d: raise EOFError()
                b+=d
            return b
        def handle(self):
            self.request.settimeout(8)
            try:
                if self.server.server_address[1]==1080:
                    v,n=self.exact(2); assert v==5; self.exact(n); self.request.sendall(b'\x05\x00')
                    v,cmd,_,typ=self.exact(4); assert cmd==1
                    if typ==1:self.exact(4)
                    elif typ==3:self.exact(self.exact(1)[0])
                    elif typ==4:self.exact(16)
                    self.exact(2); self.request.sendall(b'\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00'); label=b'US'
                else:
                    assert self.headers().startswith(b'CONNECT ')
                    self.request.sendall(b'HTTP/1.1 200 Connection established\r\n\r\n'); label=b'JP'
                self.headers(); self.request.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n'+label)
            except (OSError,EOFError): pass
    class Server(socketserver.ThreadingTCPServer): allow_reuse_address=True; daemon_threads=True
    for port in (1080,1081):
        server=Server(('203.0.113.1',port),Handler); threading.Thread(target=server.serve_forever,daemon=True).start()
    threading.Event().wait()

def main(core):
    tag='f25-'+str(os.getpid()); r,c,w=[tag+'-'+x for x in ('r','c','w')]; names=[r,c,w]; procs=[]
    def cmd(*args,check=True,**kw): return subprocess.run(args,check=check,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,**kw)
    def ns(name,*args,**kw):return cmd('ip','netns','exec',name,*args,**kw)
    def addr(ip,mac):
        ns(c,'ip','link','set','eth0','down'); ns(c,'ip','link','set','eth0','address',mac)
        ns(c,'ip','addr','flush','dev','eth0'); ns(c,'ip','addr','add',ip+'/24','dev','eth0')
        ns(c,'ip','-6','addr','add','fd00:7::101/64','dev','eth0','nodad'); ns(c,'ip','link','set','eth0','up')
        ns(c,'ip','route','replace','default','via','192.168.7.1'); ns(c,'ip','-6','route','replace','default','via','fd00:7::1')
        ns(r,'ip','neigh','flush','dev','br-lan'); ns(c,'ip','neigh','flush','dev','eth0')
    try:
        for n in names:cmd('ip','netns','add',n); ns(n,'ip','link','set','lo','up')
        for a,b,left,right in [('rc','ce',r,c),('rw','we',r,w)]:
            cmd('ip','link','add',a,'type','veth','peer','name',b); cmd('ip','link','set',a,'netns',left); cmd('ip','link','set',b,'netns',right)
        ns(c,'ip','link','set','ce','name','eth0'); ns(w,'ip','link','set','we','name','eth0')
        ns(r,'ip','link','add','br-lan','type','bridge'); ns(r,'ip','link','set','rc','master','br-lan')
        for name,dev in [(r,'rc'),(r,'rw'),(r,'br-lan'),(w,'eth0')]:ns(name,'ip','link','set',dev,'up')
        for dev,address in [('br-lan','192.168.7.1/24'),('rw','203.0.113.2/24')]:ns(r,'ip','addr','add',address,'dev',dev)
        ns(w,'ip','addr','add','203.0.113.1/24','dev','eth0'); ns(w,'ip','route','add','192.168.7.0/24','via','203.0.113.2')
        ns(r,'ip','route','add','default','via','203.0.113.1','dev','rw')
        for name,dev,address in [(r,'br-lan','fd00:7::1/64'),(r,'rw','fd00:1::2/64'),(w,'eth0','fd00:1::1/64')]:ns(name,'ip','-6','addr','add',address,'dev',dev,'nodad')
        ns(w,'ip','-6','route','add','fd00:7::/64','via','fd00:1::2')
        ns(r,'sysctl','-qw','net.ipv4.ip_forward=1','net.ipv6.conf.all.forwarding=1')
        ns(r,'ip','rule','add','fwmark','0x65/0xff','table','125','priority','10025'); ns(r,'ip','route','add','local','0.0.0.0/0','dev','lo','table','125')
        procs.append(subprocess.Popen(['ip','netns','exec',w,sys.executable,__file__,'--proxy']))
        with tempfile.TemporaryDirectory() as temp:
            temp=pathlib.Path(temp); conf=config(); conf['nodes']['us'].update(address='203.0.113.1',port='1080'); conf['nodes']['us'].pop('username'); conf['nodes']['us'].pop('password'); conf['nodes']['jp'].update(address='203.0.113.1',port='1081')
            out,_=compile(conf); file=temp/'router.json'; file.write_text(json.dumps(out))
            ns(r,core,'check','-c',str(file))
            log=open(temp/'core.log','w'); process=subprocess.Popen(['ip','netns','exec',r,core,'run','-c',str(file)],stdout=log,stderr=log); procs.append(process)
            time.sleep(1)
            if process.poll() is not None:
                log.flush()
                raise RuntimeError('Core startup failed: '+(temp/'core.log').read_text())
            for backend in ('nft',):
                rules=from_lua(policy.firewall(to_lua(conf),backend))
                if backend=='iptables':
                    for kind,exe in [('mangle','iptables-restore'),('filter','iptables-restore'),('ipv6','ip6tables-restore')]:ns(r,exe,'--noflush',input=rules[kind])
                    for exe,args in [('iptables',('-t','mangle','-I','PREROUTING','1','-j','JFA25_PROXY')),('iptables',('-I','FORWARD','1','-j','JFA25_GUARD')),('ip6tables',('-I','FORWARD','1','-j','JFA25_GUARD6')),('ip6tables',('-I','INPUT','1','-j','JFA25_DNS6')),('ip6tables',('-I','FORWARD','1','-j','JFA25_DNS6'))]:ns(r,exe,*args)
                else:ns(r,'nft','-f','-',input=rules['nft'])
                for index,label in [(0,'US'),(1,'JP')]:
                    d=conf['devices'][index]; addr(d['ip'],d['mac'])
                    got=ns(c,'curl','-fsS','--max-time','5','http://198.51.100.10:8080/').stdout
                    assert got==label,(backend,label,got)
                    assert ns(c,'ping','-6','-c','1','-W','1','fd00:1::1',check=False).returncode!=0,'Proxy IPv6 bypass'
                # Unknown/direct devices must still use ordinary routing.
                addr('192.168.7.103','02:00:00:00:00:03'); assert ns(c,'ping','-c','1','-W','1','203.0.113.1').returncode==0
                assert ns(c,'ping','-6','-c','1','-W','1','fd00:1::1').returncode==0
                for ip,mac in [('192.168.7.104','02:00:00:00:00:01'),('192.168.7.101','02:00:00:00:00:04')]:
                    addr(ip,mac); assert ns(c,'ping','-c','1','-W','1','203.0.113.1',check=False).returncode!=0,'MAC/IP mismatch leaked'
                addr('192.168.7.101','02:00:00:00:00:01')
                process.terminate(); process.wait(timeout=8)
                assert ns(c,'curl','-fsS','--max-time','2','http://203.0.113.1:1080/',check=False).returncode!=0,'Core failure fell back to direct'
                assert ns(c,'ping','-c','1','-W','1','203.0.113.1',check=False).returncode!=0,'Core failure forwarded directly'
                print(backend+': US/JP exits, direct, spoof rejection, IPv6 blocking, core failure protection passed',flush=True)
                if backend=='iptables':
                    ns(r,'iptables','-t','mangle','-F'); ns(r,'iptables','-F'); ns(r,'ip6tables','-F')
                    process=subprocess.Popen(['ip','netns','exec',r,core,'run','-c',str(file)],stdout=log,stderr=log); procs.append(process); time.sleep(1)
            log.close()
    finally:
        for p in procs:
            if p.poll() is None:p.terminate()
            try:p.wait(timeout=8)
            except subprocess.TimeoutExpired:p.kill();p.wait()
        for name in names:cmd('ip','netns','del',name,check=False)

if __name__=='__main__':
    if sys.argv[1:]==['--proxy']:proxy_server()
    else:main(str(pathlib.Path(sys.argv[1]).resolve()))

