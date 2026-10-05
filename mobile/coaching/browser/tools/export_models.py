"""Export unchanged TorchScript models; fail the build on numerical/contract mismatch."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys

import numpy as np
import onnx
import onnxruntime as ort
import torch

ROOT = Path(__file__).resolve().parents[4]


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False), encoding='utf-8')


def feature(lm, mean, std):
    xyz = np.array([[p['x'], p['y'], p['z']] for p in lm], np.float32)
    hip = xyz[[23, 24]].mean(0)
    scale = max(np.linalg.norm(xyz[[11, 12], :2].mean(0) - hip[:2]), np.linalg.norm(xyz[11, :2] - xyz[12, :2]))
    raw = np.r_[((xyz - hip) / scale).ravel(), [p['visibility'] for p in lm], [p['presence'] for p in lm]].astype(np.float32)
    return np.r_[(raw - mean) / std, np.float32(1)].astype(np.float32)


def export(bundle, target, fixtures):
    target.mkdir(parents=True, exist_ok=True)
    fixtures.mkdir(parents=True, exist_ok=True)
    meta = json.loads((bundle / 'model_metadata.json').read_text())
    assert meta['winner'] == 'exp1_full_head_attention' and meta['feature_dimension'] == 166
    assert meta['components']['main'] == [f'main_seed_{s}.pt' for s in (2026, 3407, 8111)]
    z = np.load(bundle / 'preprocessing.npz')
    mean, std = z['mean'].astype(np.float32), z['std'].astype(np.float32)
    assert mean.shape == std.shape == (165,) and np.isfinite(mean).all() and (std > 0).all()
    write(target / 'preprocessing.json', dict(dtype='float32', mean=mean.tolist(), std=std.tolist()))
    write(target / 'model_metadata.json', meta)
    shutil.copy2(bundle / 'pose_landmarker_heavy.task', target / 'pose_landmarker_heavy.task')
    rng = np.random.default_rng(2026)
    samples, landmark_cases = [], []
    for i in range(64):
        xyz = rng.uniform(-.3, 1.3, (33, 3)).astype(np.float32)
        xyz[11:13, :2] = [[.35, .25], [.65, .25]]
        xyz[23:25, :2] = [[.4, .65], [.6, .65]]
        lm = [dict(x=float(p[0]), y=float(p[1]), z=float(p[2]), visibility=float(rng.uniform(.05, 1)), presence=float(rng.uniform(.1, 1))) for p in xyz]
        x = feature(lm, mean, std)
        samples.append(x)
        landmark_cases.append(dict(landmarks=lm, features=x.tolist()))
    # Optional extracted real-pose vectors supplement deterministic numerical stress tests.
    actual = fixtures / 'image_reference.json'
    if actual.exists():
        for entry in json.loads(actual.read_text())['images']:
            if entry.get('features') is not None:
                samples.append(np.asarray(entry['features'], np.float32))
                if entry.get('landmarks') is not None:
                    landmark_cases.append(dict(landmarks=entry['landmarks'], features=entry['features']))
    for magnitude in (0., .1, 1., 3., 10.):
        for _ in range(8):
            x = rng.normal(0, magnitude, 166).astype(np.float32); x[-1] = 1; samples.append(x)
    logits_by_seed, conversions = [], []
    torch.set_num_threads(1)
    for seed in ('2026', '3407', '8111'):
        source = bundle / f'main_seed_{seed}.pt'
        model = torch.jit.load(str(source), map_location='cpu').eval()
        dest = target / f'main_seed_{seed}.onnx'
        torch.onnx.export(model, torch.zeros(1, 166), str(dest), input_names=['features'], output_names=['logits'], opset_version=17, dynamo=False)
        # Exporter may optimize the in-memory ScriptModule. Reference uses a fresh
        # load of the unchanged file, exactly as the application does.
        model = torch.jit.load(str(source), map_location='cpu').eval()
        graph = onnx.load(dest); onnx.checker.check_model(graph)
        session = ort.InferenceSession(str(dest), providers=['CPUExecutionProvider'])
        assert session.get_inputs()[0].name == 'features' and session.get_inputs()[0].shape == [1, 166]
        assert session.get_outputs()[0].name == 'logits' and session.get_outputs()[0].shape == [1, 8]
        logits, max_error = [], 0.
        for x in samples:
            with torch.no_grad(): expected = model(torch.from_numpy(x[None])).numpy()[0]
            observed = session.run(['logits'], {'features': x[None]})[0][0]
            np.testing.assert_allclose(observed, expected, atol=2e-5, rtol=2e-5)
            assert int(observed.argmax()) == int(expected.argmax())
            max_error = max(max_error, float(np.max(np.abs(observed - expected))))
            logits.append(expected.tolist())
        logits_by_seed.append(logits)
        conversions.append(dict(seed=seed, arrays=len(samples), max_absolute_logit_error=max_error, passed=True, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
    write(fixtures / 'landmarks.json', landmark_cases)
    write(fixtures / 'features.json', [dict(features=x.tolist(), logits=[logits_by_seed[j][i] for j in range(3)]) for i, x in enumerate(samples)])
    write(target / 'conversion_report.json', dict(opset=17, input_name='features', output_name='logits', shape=[1, 166], torch=torch.__version__, onnxruntime=ort.__version__, conversions=conversions))
    assets = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(target.iterdir()) if p.suffix in ('.onnx', '.json', '.task') and p.name != 'manifest.json'}
    browser = ROOT / 'mobile/coaching/browser'
    pipeline = {p.relative_to(browser).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sorted((browser / 'src').glob('*.mjs')), browser / 'scripts/mediapipe-presence.mjs', browser / 'package-lock.json']}
    digest = hashlib.sha256(json.dumps(dict(assets=assets, pipeline=pipeline), sort_keys=True).encode()).hexdigest()[:16]
    write(target / 'manifest.json', dict(schema_version='2.0.0', model_version=meta['model_version'] + '-' + digest, assets=assets, pipeline=pipeline, classes=meta['classes']))
    print(json.dumps(conversions))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, default=ROOT / 'model/deployment_bundle')
    parser.add_argument('--out', type=Path, default=ROOT / 'mobile/coaching/browser/assets')
    parser.add_argument('--fixtures', type=Path, default=ROOT / 'mobile/coaching/browser/test/fixtures')
    args = parser.parse_args(); export(args.bundle, args.out, args.fixtures)
