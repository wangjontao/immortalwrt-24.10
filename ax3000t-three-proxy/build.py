from pathlib import Path
import argparse,subprocess,json,shutil,hashlib,urllib.request,tarfile,zipfile,gzip,struct,re
P=Path(__file__).resolve().parent
ROOT=Path.cwd()
LOCK=json.loads((P/'sources.lock.json').read_text())
CORES=json.loads((P/'cores.lock.json').read_text())
def run(*args,**kw):return subprocess.run(list(args),check=True,**kw)
def patch_ssrplus_singbox():
 patch=P/'patches'/'ssrplus-singbox.patch'
 run('git','apply','--directory=package/custom-proxy-ui','--whitespace=nowarn',str(patch),cwd=ROOT)
 init=Path('package/custom-proxy-ui/luci-app-ssr-plus/root/etc/init.d/shadowsocksr').read_text(encoding='utf-8')
 monitor=Path('package/custom-proxy-ui/luci-app-ssr-plus/root/usr/bin/ssr-monitor').read_text(encoding='utf-8')
 switcher=Path('package/custom-proxy-ui/luci-app-ssr-plus/root/usr/bin/ssr-switch').read_text(encoding='utf-8')
 helper=Path('package/custom-proxy-ui/luci-app-ssr-plus/root/usr/share/shadowsocksr/gen_singbox_anytls.lua')
 server_helper=Path('package/custom-proxy-ui/luci-app-ssr-plus/root/usr/share/shadowsocksr/gen_singbox_anytls_server.lua')
 assert 'start_v2ray_with_singbox()' in init
 assert 'gen_singbox_anytls.lua' in init and helper.is_file()
 assert 'gen_singbox_anytls_server.lua' in init and server_helper.is_file()
 assert 'sing-box-server-' in monitor
 assert '${PROBE_INSTANCE_KEY}-sing-box' in switcher
def prepare():
 lines=[]
 for name in ['packages','luci','routing','telephony','pwpackages','passwall2','helloworld','openclash']:
  item=LOCK[name];lines.append(f"src-git {name} https://github.com/{item['repo']}.git^{item['sha']}")
 Path('feeds.conf.default').write_text('\n'.join(lines)+'\n')
 run('./scripts/feeds','update','-a')
 run('./scripts/feeds','install','-a')
 for feed,pkg in [('passwall2','luci-app-passwall2'),('helloworld','luci-app-ssr-plus'),('openclash','luci-app-openclash')]:
  run('./scripts/feeds','install','-f','-p',feed,pkg)
 # Explicitly replace the old LuCI providers with pinned plugin sources.
 for feed,pkg in [('passwall2','luci-app-passwall2'),('helloworld','luci-app-ssr-plus'),('openclash','luci-app-openclash')]:
  for item in Path('package/feeds').glob('*/'+pkg):
   assert item.is_symlink(),item
   item.unlink()
  shutil.copytree(Path('feeds')/feed/pkg,Path('package/custom-proxy-ui')/pkg,dirs_exist_ok=True)
 patch_ssrplus_singbox()
 # Remove installed feed providers of these exact names; use pinned official cores.
 for pkg in CORES:
  for item in Path('package/feeds').glob('*/'+pkg):
   assert item.is_symlink(),item
   item.unlink()
  shutil.copytree(P/'packages'/pkg,Path('package/custom-pinned-cores')/pkg,dirs_exist_ok=True)
 shutil.copytree(P/'files','files',dirs_exist_ok=True)
 for item in Path('files').rglob('*'):
  if item.is_file() and item.read_bytes().startswith(b'#!/bin/sh'):item.chmod(0o755)
 shutil.copy2(P/'ax3000t-ubootmod.config','.config')
 run('make','defconfig')
 required=['CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-ubootmod=y','CONFIG_PACKAGE_luci-app-passwall2=y','CONFIG_PACKAGE_geoview=y','CONFIG_PACKAGE_luci-app-ssr-plus=y','CONFIG_PACKAGE_luci-app-openclash=y','CONFIG_PACKAGE_sing-box=y','CONFIG_PACKAGE_xray-core=y','CONFIG_PACKAGE_mihomo=y','CONFIG_PACKAGE_luci-theme-argon=y','CONFIG_PACKAGE_luci-app-nps=y','CONFIG_PACKAGE_npc=y']
 config=Path('.config').read_text()
 for line in required:assert line in config,line
 assert 'CONFIG_PACKAGE_luci-app-passwall=y' not in config
 assert 'CONFIG_PACKAGE_fastacl252=y' not in config
 pw=Path('package/custom-proxy-ui/luci-app-passwall2/Makefile').read_text()
 ssr=Path('package/custom-proxy-ui/luci-app-ssr-plus/Makefile').read_text()
 oc=Path('package/custom-proxy-ui/luci-app-openclash/Makefile').read_text()
 assert '26.10.20' in pw and 'PKG_RELEASE:=1' in pw
 assert '+geoview' in pw and '+v2ray-geoip' in pw and '+v2ray-geosite' in pw
 assert 'PKG_VERSION:=198' in ssr and 'PKG_RELEASE:=2' in ssr and 'AnyTLS' in ssr
 assert '0.48.002' in oc
 print('Target, plugin versions and core selection verified.',flush=True)
def corecheck():
 out=Path('core-check');out.mkdir(exist_ok=True);Path('dl').mkdir(exist_ok=True)
 for pkg,c in CORES.items():
  archive=Path('dl')/c['source']
  if not archive.exists():run('curl','-fL','--retry','4','--connect-timeout','30','--max-time','600',c['url'],'-o',str(archive))
  assert hashlib.sha256(archive.read_bytes()).hexdigest()==c['sha256'],pkg+' checksum'
  target=out/c['binary']
  if pkg=='sing-box':
   with tarfile.open(archive) as t:
    m=next(m for m in t.getmembers() if m.isfile() and Path(m.name).name=='sing-box');target.write_bytes(t.extractfile(m).read())
  elif pkg=='mihomo':target.write_bytes(gzip.decompress(archive.read_bytes()))
  else:
   with zipfile.ZipFile(archive) as z:target.write_bytes(z.read('xray'))
  target.chmod(0o755);data=target.read_bytes();assert data[:4]==b'\x7fELF' and struct.unpack('<H',data[18:20])[0]==183,pkg+' architecture'
  phoff=struct.unpack('<Q',data[32:40])[0];entsize,count=struct.unpack('<HH',data[54:58]);assert all(struct.unpack('<I',data[phoff+i*entsize:phoff+i*entsize+4])[0]!=3 for i in range(count)),pkg+' must be static'
  args=['-v'] if pkg=='mihomo' else ['version']
  result=subprocess.run(['qemu-aarch64','-cpu','max',str(target),*args],check=True,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
  assert c['version'] in result.stdout,result.stdout
  (out/(pkg+'-version.txt')).write_text(result.stdout);print(result.stdout,flush=True)
 # Check the actual SSR Plus+ AnyTLS generator through the Sing-box binary.
 gen=Path('package/custom-proxy-ui/luci-app-ssr-plus/root/usr/share/shadowsocksr/gen_singbox_anytls.lua')
 server_gen=Path('package/custom-proxy-ui/luci-app-ssr-plus/root/usr/share/shadowsocksr/gen_singbox_anytls_server.lua')
 for mode in ['redirect','tproxy']:
  config=out/('ssr-anytls-'+mode+'.json')
  run(str(ROOT/'.venv/bin/python'),str(P/'test_ssr_anytls.py'),str(gen),str(config),mode,str(P/'testdata'))
  run('qemu-aarch64','-cpu','max',str(out/'sing-box'),'check','-c',str(config),timeout=60)
 server_config=out/'ssr-anytls-server.json'
 run(str(ROOT/'.venv/bin/python'),str(P/'test_ssr_anytls.py'),str(server_gen),str(server_config),'server',str(P/'testdata'))
 run('qemu-aarch64','-cpu','max',str(out/'sing-box'),'check','-c',str(server_config),timeout=60)
 (out/'mihomo-anytls.yaml').write_text("mixed-port: 0\nproxies:\n  - name: test\n    type: anytls\n    server: 127.0.0.1\n    port: 443\n    password: test-only-password\n    sni: example.com\nrules:\n  - MATCH,DIRECT\n")
 run('qemu-aarch64','-cpu','max',str(out/'mihomo'),'-t','-d',str(out),'-f',str(out/'mihomo-anytls.yaml'),timeout=60)
def artifacts():
 src=Path('bin/targets/mediatek/filogic');out=Path('upload');out.mkdir(exist_ok=True)
 manifest=next(src.glob('*.manifest'));text=manifest.read_text()
 for pkg,version in [('luci-app-nps','1.1'),('npc','0.26.24'),('luci-app-passwall2','26.10.20'),('geoview','0.2.8'),('luci-app-ssr-plus','198'),('luci-app-openclash','0.48.002'),('luci-theme-argon',''),('luci-app-argon-config',''),*[(k,v['version']) for k,v in CORES.items()]]:
  assert any(l.startswith(pkg+' - ') and version in l for l in text.splitlines()),(pkg,version)
 assert not any(l.startswith('luci-app-passwall - ') for l in text.splitlines()),'PassWall 1 must not be installed'
 for pkg in ['v2ray-geoip','v2ray-geosite']:
  assert any(l.startswith(pkg+' - ') for l in text.splitlines()),pkg
 images=list(src.glob('*xiaomi_mi-router-ax3000t-ubootmod*sysupgrade.itb'));assert len(images)==1,images
 assert images[0].read_bytes()[:4]==bytes.fromhex('d00dfeed')
 for p in images+[manifest]+list(src.glob('*.buildinfo')):
  shutil.copy2(p,out/p.name)
 for p in [P/'sources.lock.json',P/'cores.lock.json',P/'README.md',Path('.config')]:shutil.copy2(p,out/p.name)
 for p in Path('core-check').glob('*-version.txt'):shutil.copy2(p,out/p.name)
 (out/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in sorted(out.iterdir()) if p.is_file() and p.name!='SHA256SUMS'))
 print('Image format and installed plugin/core manifest verified.',flush=True)
if __name__=='__main__':
 phase=argparse.ArgumentParser();phase.add_argument('stage',choices=['prepare','corecheck','artifacts']);args=phase.parse_args();globals()[args.stage]()
