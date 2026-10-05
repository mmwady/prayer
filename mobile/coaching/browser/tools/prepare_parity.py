"""Offline test harness: local images/video → original Python reference JSON.

No upload or prediction endpoint. Images are copied only into a localhost acceptance
fixture directory. Do not publish the fixture directory in the production build.
"""
import argparse
import base64
import importlib.util
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageOps, ImageEnhance

ROOT = Path(__file__).resolve().parents[4]
FIXTURES = ROOT / 'mobile/coaching/browser/test/fixtures'


def pixels():
    rng = np.random.default_rng(3407)
    cases = []
    for w, h in [(23, 37), (513, 289), (800, 1025), (1800, 1100)]:
        rgb = rng.integers(0, 256, (h, w, 3), dtype=np.uint8)
        im = Image.fromarray(rgb); im.thumbnail((384, 512), Image.Resampling.LANCZOS)
        canvas = Image.new('RGB', (384, 512)); canvas.paste(im, ((384-im.width)//2, (512-im.height)//2))
        candidates = [canvas, ImageOps.autocontrast(canvas, cutoff=1), ImageEnhance.Contrast(canvas).enhance(1.15), canvas.rotate(-5, Image.Resampling.BICUBIC), canvas.rotate(5, Image.Resampling.BICUBIC)]
        cases.append(dict(width=w, height=h, rgb=base64.b64encode(rgb.tobytes()).decode(), candidates=[base64.b64encode(x.tobytes()).decode() for x in candidates]))
    FIXTURES.mkdir(parents=True, exist_ok=True)
    (FIXTURES / 'pixels.json').write_text(json.dumps(cases), encoding='utf-8')


def references(images, videos=None, count=100, augment=False):
    import torch
    torch.set_num_threads(1)
    directory = FIXTURES / 'images'; directory.mkdir(parents=True, exist_ok=True)
    paths = list(images)
    corpus_kind = 'original images / extracted video frames'
    if augment:
        corpus_kind = 'controlled robustness variants of existing images, not independent subjects or recordings'
        paths = []
        for index, original in enumerate(images):
            im = ImageOps.exif_transpose(Image.open(original)).convert('RGB')
            for variant in range(10):
                p = directory / f'variant_{index:02d}_{variant:02d}.png'
                if variant == 0: transformed = im.copy()
                elif variant < 5: transformed = ImageEnhance.Brightness(im).enhance([.55,.75,1.15,1.35][variant-1])
                elif variant < 8: transformed = im.rotate([-5,5,10][variant-5], Image.Resampling.BICUBIC)
                elif variant == 8:
                    transformed = im.copy(); transformed.thumbnail((256,384),Image.Resampling.LANCZOS)
                else: transformed = ImageEnhance.Contrast(im).enhance(.65)
                transformed.save(p); paths.append(p)
    for video_index, video in enumerate(videos or []):
        import cv2
        capture = cv2.VideoCapture(str(video)); total = capture.get(cv2.CAP_PROP_FRAME_COUNT)
        selected = {int(n): i for i, n in enumerate(np.linspace(0, max(0, total-1), count, dtype=int))}
        print(f'Extracting {count} full-resolution JPEG frames from {video.name}', flush=True)
        for frame_index in range(int(total)):
            if not capture.grab(): break
            if frame_index not in selected: continue
            ok, bgr = capture.retrieve()
            if not ok: continue
            i = selected[frame_index]
            p = directory / f'video_{video_index}_{i:03d}.jpg'
            Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)).save(p, format='JPEG', quality=95, subsampling=0)
            paths.append(p)
            if (i+1) % 20 == 0: print(f'Extracted {i+1}/{count} from video {video_index+1}', flush=True)
        capture.release()
    spec = importlib.util.spec_from_file_location('source_predictor', ROOT / 'PrayerActionRecognizer_UI/deployment_bundle/imcspd_inference.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    predictor = module.PrayerActionPredictor(ROOT / 'model/deployment_bundle')
    entries = []
    try:
        for i, path in enumerate(paths):
            # Preserve original bytes/EXIF for browser decode parity.
            target = directory / f'image_{i:03d}{path.suffix.lower()}'; target.write_bytes(path.read_bytes())
            feat, method, vis, lm, prepared = predictor._feature(target)
            result = predictor.predict(target)
            individual = []
            if feat is not None:
                tensor = torch.from_numpy(feat[None])
                for model in predictor.models['main']:
                    with torch.inference_mode(): individual.append(torch.softmax(model(tensor),1).numpy()[0].tolist())
            entries.append(dict(path='images/' + target.name, original_name=path.name, result=result,
                features=feat.tolist() if feat is not None else None,
                landmarks=[dict(x=p.x,y=p.y,z=p.z,visibility=p.visibility,presence=p.presence) for p in lm] if lm else None,
                individual_probabilities=individual))
            print(f'{i+1}/{len(paths)} {path.name}: {result["predicted_action"]}', flush=True)
    finally: predictor.close()
    (FIXTURES / 'image_reference.json').write_text(json.dumps(dict(source='unaltered Python predictor', corpus_kind=corpus_kind, original_image_count=len(images), videos=[str(v) for v in videos or []], sampled_frames_per_video=count if videos else None, extraction='one forward pass; original resolution; JPEG quality 95, 4:4:4; OpenCV native orientation' if videos else None, images=entries), ensure_ascii=False, allow_nan=False), encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--images', type=Path); parser.add_argument('--video', type=Path, action='append'); parser.add_argument('--count', type=int, default=100); parser.add_argument('--pixels-only', action='store_true'); parser.add_argument('--augment', action='store_true'); parser.add_argument('--fixtures', type=Path, default=FIXTURES)
    args = parser.parse_args(); FIXTURES=args.fixtures; pixels()
    if not args.pixels_only:
        selected = sorted(p for p in args.images.rglob('*') if p.suffix.lower() in ('.png','.jpg','.jpeg','.webp')) if args.images else []
        references(selected, args.video, args.count, args.augment)
