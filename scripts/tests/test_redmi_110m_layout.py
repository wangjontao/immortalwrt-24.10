#!/usr/bin/env python3
"""Check D-U-Boot NMBM 110MiB source layout and actual BIN image contents."""
from pathlib import Path
import argparse,struct,tarfile,tempfile,subprocess

ROOT=Path(__file__).resolve().parents[2]
def source_checks():
 dts=(ROOT/'target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dts').read_text()
 assert 'mediatek,nmbm;' in dts
 assert 'reg = <0x600000 0x6e00000>;' in dts
 assert '"xiaomi,redmi-router-ax6000"' in dts
 images=(ROOT/'target/linux/mediatek/image/filogic.mk').read_text().split('define Device/xiaomi_redmi-router-ax6000\n',1)[1].split('endef',1)[0]
 for expected in ['IMAGE_SIZE := 112640k','KERNEL_IN_UBI := 1','IMAGE/factory.bin := append-ubi','IMAGE/sysupgrade.bin := sysupgrade-tar']:
  assert expected in images,expected
 upgrade=(ROOT/'target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh').read_text().split('\txiaomi,redmi-router-ax6000)\n',1)[1].split(';;',1)[0]
 assert 'CI_UBIPART="ubi"' in upgrade and 'CI_KERNPART="kernel"' in upgrade and 'nand_do_upgrade' in upgrade
 config=(ROOT/'build-configs/JuLiangTK-Redmi-AX6000-NMBM110M-FastACL258.txt').read_text()
 assert 'CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000=y' in config
 assert 'CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-ubootmod=y' not in config
 package=(ROOT/'profiles/fastacl-v252/package-Makefile').read_text()
 assert 'PKG_VERSION:=2.6.0' in package and 'PKG_RELEASE:=2' in package
 print('PASS source: NMBM, 110MiB UBI, factory/sysupgrade BIN, upgrade label, FastACL r2')

def fdt(blob):
 h=struct.unpack_from('>10I',blob);assert h[0]==0xd00dfeed
 off=h[2];strings=h[3];end=off+h[9];stack=[];props={}
 while off<end:
  token=struct.unpack_from('>I',blob,off)[0];off+=4
  if token==1:
   e=blob.index(b'\0',off);stack.append(blob[off:e].decode());off=(e+4)&~3
  elif token==2:stack.pop()
  elif token==3:
   n,so=struct.unpack_from('>II',blob,off);off+=8;e=blob.index(b'\0',strings+so);name=blob[strings+so:e].decode();props['/'.join(stack)+'/'+name]=blob[off:off+n];off=(off+n+3)&~3
  elif token==9:break
  elif token!=4:raise AssertionError('Invalid DT token')
 return props,h[1]

def image_checks(factory,sysupgrade):
 assert factory.suffix=='.bin' and sysupgrade.suffix=='.bin'
 assert 5*1024*1024<factory.stat().st_size<=0x6e00000
 with factory.open('rb')as f:first=f.read(128*1024)
 assert first[:4]==b'UBI#','Factory image is not raw UBI'
 vid_offset,data_offset=struct.unpack_from('>II',first,16)
 assert first[vid_offset:vid_offset+4]==b'UBI!','Invalid factory VID header'
 names=[]
 for i in range(128):
  entry=first[data_offset+i*172:data_offset+(i+1)*172]
  if len(entry)<172:break
  if struct.unpack_from('>I',entry)[0]:
   length=struct.unpack_from('>H',entry,14)[0]
   if 0<length<=127:names.append(entry[16:16+length].decode())
 assert 'kernel'in names and 'rootfs'in names,('Missing UBI firmware volumes',names)
 with tarfile.open(sysupgrade,'r:')as tf:
  members={m.name:m for m in tf.getmembers()}
  kernel_name=next(n for n in members if n.endswith('/kernel'))
  rootfs_name=next(n for n in members if n.endswith('/root'))
  assert kernel_name.startswith('sysupgrade-xiaomi_redmi-router-ax6000/')
  kernel=tf.extractfile(kernel_name).read();rootfs=tf.extractfile(rootfs_name).read()
 assert rootfs[:4]==b'hsqs','Root filesystem is not SquashFS'
 fit,size=fdt(kernel);node=next(k.rsplit('/',1)[0] for k in fit if k.startswith('/images/')and k.endswith('/type')and fit[k].rstrip(b'\0')==b'flat_dt')
 dt=fit.get(node+'/data')
 if dt is None:
  pos=struct.unpack('>I',fit[node+'/data-position'])[0]if node+'/data-position'in fit else size+struct.unpack('>I',fit[node+'/data-offset'])[0]
  n=struct.unpack('>I',fit[node+'/data-size'])[0];dt=kernel[pos:pos+n]
 props,_=fdt(dt)
 assert b'xiaomi,redmi-router-ax6000\0'in props['/compatible']
 assert any(k.endswith('/mediatek,nmbm')for k in props)
 assert any(k.endswith('/partition@600000/reg')and v==struct.pack('>II',0x600000,0x6e00000)for k,v in props.items())
 assert not any(k.endswith('/volname')and v==b'fit\0'for k,v in props.items())
 with tempfile.TemporaryDirectory()as tmp:
  p=Path(tmp)/'rootfs.squashfs';p.write_bytes(rootfs)
  for name,minimum in [('cn-ipv4.txt',1000),('cn-domains.txt',10000)]:
   data=subprocess.check_output(['unsquashfs','-cat',str(p),'usr/share/fastacl252/'+name],stderr=subprocess.PIPE)
   count=sum(bool(x.strip())and not x.startswith(b'#')for x in data.splitlines());assert count>=minimum,(name,count)
   print('PASS packaged r2 DNS/split dataset:',name,count)
 print('PASS BIN images: UBI kernel/rootfs, sysupgrade tar, actual NMBM 110MiB DTB, SquashFS')

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--factory',type=Path);parser.add_argument('--sysupgrade',type=Path);args=parser.parse_args()
 source_checks()
 if args.factory or args.sysupgrade:
  assert args.factory and args.sysupgrade
  image_checks(args.factory,args.sysupgrade)
