"""Reject incomplete or tampered web releases before activation."""
import hashlib
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1]).resolve()
manifest = json.loads((root / 'iqtadi-offline-manifest.json').read_text())
for name in ['index.html', 'main.dart.js', 'recognizer/bridge.js', 'iqtadi_service_worker.js']:
    assert (root / name).is_file(), name
for item in manifest['files']:
    path = (root / item['path']).resolve()
    assert path.is_relative_to(root), item['path']
    assert path.is_file(), item['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256'], item['path']
assert manifest['version'] in (root / 'iqtadi_service_worker.js').read_text()
print(json.dumps({'verified_files': len(manifest['files']), 'version': manifest['version']}))
