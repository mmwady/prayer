import { decode, hasPngSignature } from 'fast-png';
import { pixelsFromBitmap } from './image.mjs';
export function orientRGB(image, orientation = 1) {
  const { width: w, height: h, data } = image;
  if (orientation < 2 || orientation > 8) return image;
  const ow = orientation >= 5 ? h : w, oh = orientation >= 5 ? w : h, out = new Uint8Array(data.length);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const [dx, dy] = { 2:[w-1-x,y], 3:[w-1-x,h-1-y], 4:[x,h-1-y], 5:[y,x], 6:[h-1-y,x], 7:[h-1-y,w-1-x], 8:[y,w-1-x] }[orientation];
    out.set(data.subarray((y*w+x)*3,(y*w+x)*3+3),(dy*ow+dx)*3);
  }
  return { width: ow, height: oh, data: out };
}
function exifOrientation(bytes) {
  try {
    const view = new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength), little = view.getUint16(0) === 0x4949;
    if (view.getUint16(2,little) !== 42) return 1;
    const start=view.getUint32(4,little), count=view.getUint16(start,little);
    for(let i=0;i<count;i++){const p=start+2+i*12;if(view.getUint16(p,little)===274 && view.getUint16(p+2,little)===3 && view.getUint32(p+4,little)===1)return view.getUint16(p+8,little);}
  } catch { /* Invalid optional EXIF has no usable orientation. */ }
  return 1;
}
export function pngRGB(bytes) {
  const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
  const w=view.getUint32(16),h=view.getUint32(20);
  if(!w || !h || w*h>40000000)throw Error('Image exceeds the 40-megapixel local processing limit');
  if(bytes[24]<8 && bytes[28]===1)throw Error('Interlaced PNG with bit depth below 8 is unsupported; use an RGB PNG or JPEG');
  const png=decode(bytes,{checkCrc:true}), data=new Uint8Array(png.width*png.height*3);
  for(let y=0;y<png.height;y++)for(let x=0;x<png.width;x++){
    const i=y*png.width+x;let rgb;
    if(png.depth<8){const rowBytes=Math.ceil(png.width*png.depth/8),bit=x*png.depth;const v=(png.data[y*rowBytes+Math.floor(bit/8)]>>(8-png.depth-bit%8))&((1<<png.depth)-1);rgb=png.palette?png.palette[v].slice(0,3):Array(3).fill(Math.round(v*255/((1<<png.depth)-1)));}
    else if(png.palette)rgb=png.palette[png.data[i]].slice(0,3);
    else if(png.channels<=2){const v=png.depth===16?Math.min(255,png.data[i*png.channels]):png.data[i*png.channels];rgb=[v,v,v];}
    else rgb=[0,1,2].map(c=>png.depth===16?png.data[i*png.channels+c]>>>8:png.data[i*png.channels+c]);
    data.set(rgb,i*3); // Pillow convert('RGB') drops alpha; it does not composite.
  }
  let orientation=1;
  for(let p=8;p+12<=bytes.length;){const length=view.getUint32(p),name=String.fromCharCode(...bytes.subarray(p+4,p+8));if(p+12+length>bytes.length)break;if(name==='eXIf')orientation=exifOrientation(bytes.subarray(p+8,p+8+length));p+=12+length;}
  return orientRGB({data,width:png.width,height:png.height},orientation);
}
export async function pixelsFromSource(source) {
  if(source instanceof Blob){
    if(source.size>50000000)throw Error('Image exceeds the 50 MB local processing limit');
    const bytes=new Uint8Array(await source.arrayBuffer());
    if(hasPngSignature(bytes))return pngRGB(bytes);
    if(typeof createImageBitmap==='function'){
      const bitmap=await createImageBitmap(source,{imageOrientation:'from-image',premultiplyAlpha:'none',colorSpaceConversion:'none'});
      try{return pixelsFromBitmap(bitmap);}finally{bitmap.close();}
    }
    const url=URL.createObjectURL(source),image=new Image();
    try{image.src=url;await image.decode();return pixelsFromBitmap(image);}finally{URL.revokeObjectURL(url);}
  }
  return pixelsFromBitmap(source);
}
