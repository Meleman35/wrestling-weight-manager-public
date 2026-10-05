import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createRemoteJPEGNormalizer} from '../src/remote-weighins-jpeg.mjs';
const codec=createRequire(import.meta.url)('jpeg-js');
const normalize=createRemoteJPEGNormalizer({codec});
const fixture=(width=32,height=48)=>({width,height,data:new Uint8Array(width*height*4).fill(150)});
test('maximum permitted square frame fits the decoder resource budget',()=>{
 const result=normalize(codec.encode(fixture(1280,1280),80).data);
 const decoded=codec.decode(result);
 assert.equal(decoded.width,1280);assert.equal(decoded.height,1280);
});
test('full JPEG decode and encode preserve portrait framing and remove metadata',()=>{
 const raw=fixture(480,640),jpeg=codec.encode({...raw,comments:['Synthetic location must not survive'],exifBuffer:new Uint8Array([69,120,105,102,0,0,71,80,83])},80).data;
 const result=normalize(jpeg),decoded=codec.decode(result);
 assert.equal(decoded.width,480);assert.equal(decoded.height,640);
 assert.equal(decoded.exifBuffer,undefined);assert.equal(decoded.comments,undefined);
 assert.equal(Buffer.from(result).includes(Buffer.from('Synthetic location')),false);
 assert.deepEqual(normalize(jpeg),result,'Identical original capture bytes must produce identical stored bytes');
});
test('markers alone, truncated image data and non-JPEG inputs fail closed',()=>{
 const jpeg=codec.encode(fixture(),80).data;
 assert.throws(()=>normalize(new Uint8Array([255,216,255,217])),/JPEG/);
 assert.throws(()=>normalize(new Uint8Array([1,2,3,4])),/JPEG/);
 const sos=jpeg.findIndex((x,i)=>x===255&&jpeg[i+1]===218);
 assert.throws(()=>normalize(new Uint8Array([...jpeg.subarray(0,sos+4),255,217])),/JPEG/);
});
test('dimension and byte limits reject input before decoder allocation',()=>{
 let calls=0;const guarded=createRemoteJPEGNormalizer({codec:{decode:()=>{calls++;},encode:codec.encode}});
 const jpeg=new Uint8Array(codec.encode(fixture(),80).data);
 const sof=jpeg.findIndex((x,i)=>x===255&&jpeg[i+1]===192);assert.ok(sof>0);
 jpeg[sof+7]=255;jpeg[sof+8]=255;
 assert.throws(()=>guarded(jpeg),/JPEG/);
 assert.throws(()=>guarded(new Uint8Array(5*1024*1024+1)),/JPEG/);
 assert.equal(calls,0);
});
test('decoder resource errors and incomplete pixel buffers reject the capture',()=>{
 const jpeg=codec.encode(fixture(),80).data;
 for(const decode of [()=>{throw Error('Memory budget');},()=>({width:32,height:48,data:new Uint8Array(1)})]){
  assert.throws(()=>createRemoteJPEGNormalizer({codec:{decode,encode:codec.encode}})(jpeg),/JPEG/);
 }
});
