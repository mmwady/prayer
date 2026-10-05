"""Exercise real release cutover/rollback with fake Docker/HTTP, never live services."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
RELEASE = 'gha-1-1-' + 'a' * 40

@unittest.skipUnless(os.name == 'posix', 'Deployment runs on Linux')
class DeploymentTests(unittest.TestCase):
    def run_case(self, target, fail_health=False, bad_hash=False):
        with tempfile.TemporaryDirectory(prefix='iqtadi-deploy-test-') as folder:
            base = Path(folder)
            for name in ['deploy', 'shared/data', 'releases/old/web', 'bin', f'incoming/{RELEASE}']:
                (base / name).mkdir(parents=True)
            (base / 'shared/data/marker').write_text('original')
            (base / 'shared/backend.env').write_text('')
            (base / 'deploy/public-url.txt').write_text('https://vps-c79afd97.vps.ovh.ca\n')
            old = base / 'releases/old'
            (base / 'current').symlink_to(old)
            incoming = base / 'incoming' / RELEASE
            shutil.copy(HERE / 'verify-web.py', incoming)
            files = {'index.html': b'index', 'main.dart.js': b'app', 'recognizer/bridge.js': b'bridge', 'iqtadi_service_worker.js': b'offline123'}
            manifest = {'version': 'offline123', 'files': [{'path': p, 'sha256': hashlib.sha256(v).hexdigest()} for p, v in files.items()]}
            if bad_hash: manifest['files'][0]['sha256'] = '0' * 64
            files['iqtadi-offline-manifest.json'] = json.dumps(manifest).encode()
            def archive(path, content):
                with tarfile.open(path, 'w:gz') as tar:
                    for name, data in content.items():
                        item = tarfile.TarInfo(name); item.size = len(data); item.mode = 0o644
                        tar.addfile(item, io.BytesIO(data))
            archive(incoming / 'web.tar.gz', files)
            archive(incoming / 'backend.tar.gz', {'deploy/vps/Dockerfile': b'FROM scratch', 'deploy/vps/run-backend.sh': (HERE / 'run-backend.sh').read_bytes()})
            fake = '''#!/usr/bin/env python3
import os,sys,pathlib
base=pathlib.Path(os.environ['TEST_BASE']);name=pathlib.Path(sys.argv[0]).name;a=sys.argv[1:]
with (base/'calls').open('a') as f:f.write(name+' '+ ' '.join(a)+'\\n')
if name=='docker':
 if a[0]=='inspect':print('old-image' if '.Config.Image' in a[2] else 'healthy')
 elif a[0]=='run':
  if a[a.index('--name')+1]=='iqtadi-backend' and a[-1]!='old-image':(base/'shared/data/marker').write_text('new-version')
  print('container-id')
elif name=='install':pathlib.Path(a[-1]).mkdir(parents=True,exist_ok=True)
elif name=='curl':
 url=a[-1]
 if url.endswith('/healthz'):
  if os.environ['FAIL_HEALTH']=='1':sys.exit(22)
  print('{"status":"ok"}')
 elif url.endswith('/admin'):print('404',end='')
 else:sys.stdout.buffer.write((base/'current/web'/url.split('.ovh.ca/',1)[1]).read_bytes())
'''
            for name in ['docker', 'curl', 'nginx', 'install']:
                p = base / 'bin' / name; p.write_text(fake); p.chmod(0o755)
            script = base / 'run.sh'
            script.write_text((HERE / 'deploy-release.sh').read_text().replace('base=/srv/iqtadi', 'base=' + str(base)))
            env = {**os.environ, 'PATH': str(base / 'bin') + os.pathsep + os.environ['PATH'], 'TEST_BASE': str(base), 'FAIL_HEALTH': str(int(fail_health))}
            result = subprocess.run(['bash', str(script), RELEASE, target], env=env, capture_output=True, text=True, timeout=20)
            calls = (base / 'calls').read_text()
            if fail_health:
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual((base / 'current').resolve(), old)
                self.assertEqual((base / 'shared/data/marker').read_text(), 'original')
                self.assertEqual((base / 'backups' / RELEASE / 'failed-data/marker').read_text(), 'new-version')
                self.assertIn('old-image', calls)
            elif bad_hash:
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((base / 'current').resolve(), old)
                self.assertNotIn('docker stop', calls)
                self.assertEqual((base / 'shared/data/marker').read_text(), 'original')
            else:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((base / 'current').resolve(), base / 'releases' / RELEASE)
                self.assertNotIn('docker stop', calls)
                self.assertEqual((base / 'shared/data/marker').read_text(), 'original')

    def test_web_activation_preserves_backend(self): self.run_case('web')
    def test_failed_combined_release_restores_web_container_and_data(self): self.run_case('both', fail_health=True)
    def test_tampered_web_is_rejected_before_backend_stop(self): self.run_case('both', bad_hash=True)

if __name__ == '__main__': unittest.main()
