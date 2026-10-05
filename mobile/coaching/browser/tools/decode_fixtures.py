import base64
import io
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageOps
ROOT=Path(__file__).resolve().parents[4]
rng=np.random.default_rng(2026)
cases=[]
images=[Image.fromarray(rng.integers(0,256,(45,32,4),dtype=np.uint8),'RGBA'),
    Image.fromarray(rng.integers(0,256,(45,32),dtype=np.uint8),'L'),
    Image.fromarray(rng.integers(0,65536,(45,32),dtype=np.uint16)),
    Image.fromarray(rng.integers(0,256,(45,32,2),dtype=np.uint8),'LA')]
images.append(images[0].convert('RGB').quantize(colors=16))
images.append(images[1].convert('1'))
for im in images:
    for orientation in range(1,9):
        exif=Image.Exif();exif[274]=orientation
        buffer=io.BytesIO();im.save(buffer,format='PNG',exif=exif)
        expected=ImageOps.exif_transpose(Image.open(io.BytesIO(buffer.getvalue()))).convert('RGB')
        cases.append(dict(mode=im.mode,orientation=orientation,png=base64.b64encode(buffer.getvalue()).decode(),width=expected.width,height=expected.height,rgb=base64.b64encode(expected.tobytes()).decode()))
(ROOT/'mobile/coaching/browser/test/fixtures/decode.json').write_text(json.dumps(cases),encoding='utf-8')
print(f'{len(cases)} Pillow PNG RGB/EXIF fixtures')
