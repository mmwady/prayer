// Pillow-compatible RGB transforms. Algorithms referenced in docs/BROWSER_INFERENCE_SPEC.md.
const clip = x => Math.max(0, Math.min(255, Math.trunc(x)));
const sinc = x => x === 0 ? 1 : Math.sin(x * Math.PI) / (x * Math.PI);
const lanczos = x => x >= -3 && x < 3 ? sinc(x) * sinc(x / 3) : 0;
export function thumbnailSize(w, h) {
  if (w <= 384 && h <= 512) return [w, h];
  const aspect = w / h;
  const best = (v, error) => Math.max(1, error(Math.floor(v)) <= error(Math.ceil(v)) ? Math.floor(v) : Math.ceil(v));
  return 384 / 512 >= aspect ? [best(512 * aspect, n => Math.abs(aspect - n / 512)), 512]
    : [384, best(384 / aspect, n => n === 0 ? 0 : Math.abs(aspect - 384 / n))];
}
function coefficients(input, extent, output) {
  const scale = Math.fround(extent) / output, filterScale = Math.max(1, scale), support = 3 * filterScale;
  return Array.from({ length: output }, (_, i) => {
    const center = (i + .5) * scale;
    const start = Math.max(0, Math.trunc(center - support + .5));
    const end = Math.min(input, Math.trunc(center + support + .5));
    const weights = Array.from({ length: end - start }, (_, j) => lanczos((j + start - center + .5) / filterScale));
    const sum = weights.reduce((a, b) => a + b, 0);
    return { start, weights: weights.map(w => { const v = sum ? w / sum : w; return Math.trunc(v * 4194304 + (v < 0 ? -.5 : .5)); }) };
  });
}
function resizeAxis(image, output, horizontal, extent) {
  const { data, width, height } = image, input = horizontal ? width : height;
  if (input === output && extent === input) return image;
  const coeff = coefficients(input, extent, output);
  const ow = horizontal ? output : width, oh = horizontal ? height : output;
  const pixels = new Uint8Array(ow * oh * 3);
  for (let y = 0; y < oh; y++) for (let x = 0; x < ow; x++) {
    const { start, weights } = coeff[horizontal ? x : y];
    for (let c = 0; c < 3; c++) {
      let sum = 2097152;
      for (let j = 0; j < weights.length; j++) {
        const idx = horizontal ? (y * width + start + j) * 3 + c : ((start + j) * width + x) * 3 + c;
        sum += data[idx] * weights[j];
      }
      pixels[(y * ow + x) * 3 + c] = clip(Math.floor(sum / 4194304));
    }
  }
  return { data: pixels, width: ow, height: oh };
}
function reduce(image, fx, fy) {
  if (fx === 1 && fy === 1) return image;
  const w = Math.ceil(image.width / fx), h = Math.ceil(image.height / fy), data = new Uint8Array(w * h * 3);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const nx = Math.min(fx, image.width - x * fx), ny = Math.min(fy, image.height - y * fy), count = nx * ny;
    const multiplier = Math.floor(16777216 / count); // Pillow reciprocal, 24-bit precision.
    for (let c = 0; c < 3; c++) {
      let sum = Math.floor(count / 2);
      for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) sum += image.data[((y * fy + j) * image.width + x * fx + i) * 3 + c];
      data[(y * w + x) * 3 + c] = Math.floor(sum * multiplier / 16777216);
    }
  }
  return { data, width: w, height: h };
}
export function letterbox(image) {
  const [w, h] = thumbnailSize(image.width, image.height);
  const fx = Math.max(1, Math.trunc(image.width / w / 2)), fy = Math.max(1, Math.trunc(image.height / h / 2));
  const extentX = image.width / fx, extentY = image.height / fy;
  let resized = reduce(image, fx, fy);
  resized = resizeAxis(resized, w, true, extentX);
  resized = resizeAxis(resized, h, false, extentY);
  const data = new Uint8Array(384 * 512 * 3), left = Math.floor((384 - w) / 2), top = Math.floor((512 - h) / 2);
  for (let y = 0; y < h; y++) data.set(resized.data.subarray(y * w * 3, (y + 1) * w * 3), ((top + y) * 384 + left) * 3);
  return { data, width: 384, height: 512 };
}
export function autocontrast(image) {
  const data = new Uint8Array(image.data.length), count = image.width * image.height;
  for (let c = 0; c < 3; c++) {
    const hist = new Uint32Array(256);
    for (let i = c; i < data.length; i += 3) hist[image.data[i]]++;
    let cut = Math.floor(count / 100);
    for (let i = 0; i < 256 && cut > 0; i++) { const n = Math.min(hist[i], cut); hist[i] -= n; cut -= n; }
    cut = Math.floor(count / 100);
    for (let i = 255; i >= 0 && cut > 0; i--) { const n = Math.min(hist[i], cut); hist[i] -= n; cut -= n; }
    let lo = 0, hi = 255;
    while (lo < 255 && !hist[lo]) lo++;
    while (hi > 0 && !hist[hi]) hi--;
    const scale = 255 / (hi - lo), offset = -lo * scale;
    for (let i = c; i < data.length; i += 3) data[i] = hi <= lo ? image.data[i] : clip(image.data[i] * scale + offset);
  }
  return { ...image, data };
}
export function contrast(image) {
  let sum = 0;
  for (let i = 0; i < image.data.length; i += 3) sum += Math.floor((19595 * image.data[i] + 38470 * image.data[i + 1] + 7471 * image.data[i + 2] + 32768) / 65536);
  const mean = Math.floor(sum / (image.width * image.height) + .5), alpha = Math.fround(1.15);
  return { ...image, data: Uint8Array.from(image.data, v => clip(Math.fround(mean + Math.fround(alpha * (v - mean))))) };
}
function cubic(v1, v2, v3, v4, d) {
  return v2 + d * (-v1 + v3 + d * (2 * (v1 - v2) + v3 - v4 + d * (-v1 + v2 - v3 + v4)));
}
export function rotate(image, degrees) {
  const { width: w, height: h } = image, data = new Uint8Array(image.data.length);
  const angle = -(((degrees % 360) + 360) % 360) * Math.PI / 180;
  const a = Number(Math.cos(angle).toFixed(15)), b = Number(Math.sin(angle).toFixed(15)), d = -b, e = a;
  const tx = a * (-w / 2) + b * (-h / 2) + w / 2, ty = d * (-w / 2) + e * (-h / 2) + h / 2;
  const clampX = x => Math.max(0, Math.min(w - 1, x));
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const sx = a * (x + .5) + b * (y + .5) + tx, sy = d * (x + .5) + e * (y + .5) + ty;
    if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue;
    const ix = Math.floor(sx - .5), iy = Math.floor(sy - .5), dx = sx - .5 - ix, dy = sy - .5 - iy;
    for (let c = 0; c < 3; c++) {
      const rows = [];
      for (let k = 0; k < 4; k++) {
        let yy = iy - 1 + k;
        if (k > 0 && (yy < 0 || yy >= h)) { rows.push(rows[k - 1]); continue; }
        yy = Math.max(0, Math.min(h - 1, yy));
        rows.push(cubic(...[0, 1, 2, 3].map(j => image.data[(yy * w + clampX(ix - 1 + j)) * 3 + c]), dx));
      }
      data[(y * w + x) * 3 + c] = clip(cubic(...rows, dy));
    }
  }
  return { ...image, data };
}
export function recoveryImage(image, index) {
  return [() => image, () => autocontrast(image), () => contrast(image), () => rotate(image, -5), () => rotate(image, 5)][index]();
}
export function canvasFor(image) {
  const canvas = typeof OffscreenCanvas !== 'undefined' ? new OffscreenCanvas(image.width, image.height) : Object.assign(document.createElement('canvas'), { width: image.width, height: image.height });
  const rgba = new Uint8ClampedArray(image.width * image.height * 4);
  for (let i = 0, j = 0; i < image.data.length; i += 3, j += 4) { rgba.set(image.data.subarray(i, i + 3), j); rgba[j + 3] = 255; }
  canvas.getContext('2d').putImageData(new ImageData(rgba, image.width, image.height), 0, 0);
  return canvas;
}
export function pixelsFromBitmap(bitmap) {
  const width = bitmap.videoWidth || bitmap.naturalWidth || bitmap.width, height = bitmap.videoHeight || bitmap.naturalHeight || bitmap.height;
  if (!width || !height || width * height > 40000000) throw Error('Invalid image dimensions or image exceeds 40 megapixels');
  const canvas = typeof OffscreenCanvas !== 'undefined' ? new OffscreenCanvas(width, height) : Object.assign(document.createElement('canvas'), { width, height });
  const ctx = canvas.getContext('2d', { willReadFrequently: true }); ctx.drawImage(bitmap, 0, 0);
  const rgba = ctx.getImageData(0, 0, width, height).data, data = new Uint8Array(width * height * 3);
  for (let i = 0, j = 0; i < rgba.length; i += 4, j += 3) data.set(rgba.subarray(i, i + 3), j);
  return { data, width, height };
}
