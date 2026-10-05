import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pngRGB } from '../src/decode.mjs';
test('48 PNG fixtures match Pillow RGB conversion and all EXIF orientations including transparent/palette/grayscale',()=>{
 const fixtures=JSON.parse(readFileSync(new URL('fixtures/decode.json',import.meta.url),'utf8'));
 for(const f of fixtures){const actual=pngRGB(new Uint8Array(Buffer.from(f.png,'base64')));assert.equal(actual.width,f.width);assert.equal(actual.height,f.height);assert.deepEqual(Buffer.from(actual.data),Buffer.from(f.rgb,'base64'),f.mode+' orientation '+f.orientation);}
});
