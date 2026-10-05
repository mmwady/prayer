"""Generate a consent-free synthetic 26-second Fajr integration video.

Run from backend/: python tools/create_mock_demo.py
No model, person, provider or camera is involved. This tests video transport only.
"""
from pathlib import Path
import shutil
import subprocess

import cv2
import numpy as np

target = Path('../docs/demo/fajr_synthetic.mp4')
target.parent.mkdir(parents=True, exist_ok=True)
ffmpeg = shutil.which('ffmpeg')
if not ffmpeg:
    raise RuntimeError('FFMPEG_REQUIRED_FOR_BROWSER_COMPATIBLE_H264_DEMO')
writer = subprocess.Popen([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
    '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-s', '640x360', '-r', '10', '-i', 'pipe:0',
    '-an', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(target)],
    stdin=subprocess.PIPE)
try:
    for index in range(260):
        image = np.zeros((360, 640, 3), dtype=np.uint8)
        image[:] = (35 + (index // 20) * 8, 65, 35)
        cv2.putText(image, 'SYNTHETIC PIPELINE DEMO - NO AI', (25, 65),
                    cv2.FONT_HERSHEY_SIMPLEX, .8, (255, 255, 255), 2)
        cv2.putText(image, f'Original video time: {index / 10:.1f}s', (40, 180),
                    cv2.FONT_HERSHEY_SIMPLEX, .85, (255, 255, 255), 2)
        cv2.putText(image, f'Script slot: {index // 20 + 1} / 13', (40, 260),
                    cv2.FONT_HERSHEY_SIMPLEX, .8, (255, 255, 255), 2)
        writer.stdin.write(image.tobytes())
finally:
    writer.stdin.close()
    writer.wait()
if writer.returncode:
    raise RuntimeError('MP4_ENCODER_FAILED')
print(target.resolve())
