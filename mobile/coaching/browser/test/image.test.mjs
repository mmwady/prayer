import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { thumbnailSize, letterbox, recoveryImage } from '../src/image.mjs';
test('thumbnail preserves aspect and never enlarges',()=>{
 assert.deepEqual(thumbnailSize(100,80),[100,80]); assert.deepEqual(thumbnailSize(800,400),[384,192]); assert.deepEqual(thumbnailSize(400,800),[256,512]);
 const im=letterbox({width:2,height:2,data:Uint8Array.from(Array(12).fill(255))}); assert.equal(im.data[0],0); assert.equal(im.data[(255*384+191)*3],255);
});
test('Pillow RGB pixel fixtures for resizing and all recovery transforms',()=>{
 const fixtures=JSON.parse(readFileSync(new URL('fixtures/pixels.json',import.meta.url),'utf8'));
 for(const fixture of fixtures){const image={width:fixture.width,height:fixture.height,data:Uint8Array.from(Buffer.from(fixture.rgb,'base64'))}; const prepared=letterbox(image);
  fixture.candidates.forEach((reference,i)=>{const expected=Buffer.from(reference,'base64'), actual=recoveryImage(prepared,i).data; let different=0,max=0; for(let j=0;j<actual.length;j++){const d=Math.abs(actual[j]-expected[j]); if(d)different++;max=Math.max(max,d);} assert.equal(different,0,`${fixture.width}x${fixture.height} recovery ${i}: ${different} differing channels, max ${max}`);});
 }
});
