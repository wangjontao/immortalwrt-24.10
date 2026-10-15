"""Retry failures at the feeds command boundary without contacting GitHub."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/ci-update-feeds.sh'


@unittest.skipUnless(shutil.which('sh'), 'POSIX shell required')
class FeedUpdateTests(unittest.TestCase):
    def run_feed_update(self, failures=0, missing=False, config=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            if config:
                (root / 'feeds.conf.default').write_text(
                    '# comment\nsrc-git packages https://github.com/immortalwrt/packages.git;openwrt-24.10\n'
                    'src-git luci https://github.com/immortalwrt/luci.git;openwrt-24.10\n')
            stub = root / 'scripts/feeds'
            stub.write_text('#!' + sys.executable.replace(chr(92), '/') + '''
import json,os,pathlib,sys
p=pathlib.Path('calls.json')
calls=json.loads(p.read_text()) if p.exists() else []
assert os.environ['GIT_CONFIG_KEY_0']=='http.https://github.com/.extraheader'
assert os.environ['GIT_CONFIG_VALUE_0']==''
assert os.environ['GIT_CONFIG_VALUE_1']=='HTTP/1.1'
calls.append(sys.argv[1:]);p.write_text(json.dumps(calls))
name=sys.argv[-1]
attempt=sum(c[-1]==name for c in calls)
if name=='packages' and attempt<=int(os.environ['TEST_FAILURES']):sys.exit(1)
if os.environ['TEST_MISSING']!='1':pathlib.Path('feeds',name).mkdir(parents=True,exist_ok=True)
''', newline='\n')
            stub.chmod(0o755)
            env = dict(os.environ, FEEDS_RETRY_DELAY='0', TEST_FAILURES=str(failures),
                       TEST_MISSING='1' if missing else '0')
            result = subprocess.run([shutil.which('sh'), str(SCRIPT).replace(chr(92), '/')], cwd=root, env=env,
                                    text=True, capture_output=True, timeout=10)
            calls = json.loads((root / 'calls.json').read_text()) if (root / 'calls.json').exists() else []
            return result, calls

    def test_transient_failure_retries_only_failed_feed(self):
        result, calls = self.run_feed_update(failures=1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [['update', 'packages'], ['update', 'packages'], ['update', 'luci']])

    def test_persistent_failure_stops_after_three_attempts(self):
        result, calls = self.run_feed_update(failures=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [['update', 'packages']] * 3)
        self.assertIn('refusing to build', result.stderr)

    def test_missing_directory_is_not_accepted(self):
        result, calls = self.run_feed_update(missing=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)

    def test_missing_configuration_is_not_accepted(self):
        result, calls = self.run_feed_update(config=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
