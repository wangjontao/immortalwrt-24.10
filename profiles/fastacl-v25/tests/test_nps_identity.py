"""Run the actual MAC discovery shell code against isolated WAN fixtures."""
import os,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class WANIdentityTests(unittest.TestCase):
 def run_key(self,device='wan',mac='02:ab:cd:12:34:56',bridge=False,alias=False):
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp);net=root/'net';(net/'wan').mkdir(parents=True);(net/'wan/address').write_text(mac)
   (net/'lan').mkdir();(net/'lan/address').write_text('02:00:00:00:00:11')
   if bridge:
    (net/'br-wan').mkdir();(net/'br-wan/address').write_text('02:00:00:00:00:99');(net/'br-wan/lower_wan').symlink_to(net/'wan',target_is_directory=True);device='br-wan'
   bindir=root/'bin';bindir.mkdir();uci=bindir/'uci';uci.write_text('#!/bin/sh\ncase "$3" in network.wan.device) printf "%s\\n" "$TEST_DEV";; network.uplink.device) echo wan;; *) exit 1;; esac\n');uci.chmod(0o755)
   env=dict(os.environ,PATH=str(bindir)+os.pathsep+os.environ['PATH'],NPS_SYS_NET=str(net),TEST_DEV='@uplink' if alias else device)
   return subprocess.run(['sh',str(ROOT/'root/usr/libexec/nps-wan-mac'),'--print-key'],env=env,capture_output=True,text=True,timeout=5)
 def test_physical_identity_uppercase_no_colons(self):
  r=self.run_key();self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(r.stdout.strip(),'02ABCD123456')
 def test_bridge_reads_lower_wan_not_bridge_mac(self):
  self.assertEqual(self.run_key(bridge=True).stdout.strip(),'02ABCD123456')
 def test_logical_interface_alias(self):
  self.assertEqual(self.run_key(alias=True).stdout.strip(),'02ABCD123456')
 def test_missing_wan_never_falls_back_to_lan(self):
  self.assertNotEqual(self.run_key(device='missing-wan').returncode,0)
 def test_invalid_mac_rejected(self):
  for mac in ['00:00:00:00:00:00','ff:ff:ff:ff:ff:ff','FF:FF:FF:FF:FF:FF','zz:ab:cd:12:34:56']:
   with self.subTest(mac=mac):
    r=self.run_key(mac=mac);self.assertNotEqual(r.returncode,0,r.stdout+r.stderr)
if __name__=='__main__':unittest.main(verbosity=2)
