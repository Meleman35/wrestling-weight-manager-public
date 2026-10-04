import {test} from 'node:test';import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createRemoteJPEGNormalizer} from '../src/remote-weighins-jpeg.mjs';
const codec=createRequire(import.meta.url)('jpeg-js'),normalizeJPEG=createRemoteJPEGNormalizer({codec});
const jpeg=codec.encode({width:4,height:4,data:new Uint8Array(64).fill(180)},80).data;
import {createRemotePhotoProvider} from '../src/remote-weighins-photos.mjs';
function fixture(){const files=new Map(),rows=new Map();let allowed=true,lost=false,revokedAfterDownload=false,expireAfterDownload=false;
 const authorize=async()=>{if(!allowed)throw Error('Revoked');};
 const bucket={upload:async(path,bytes)=>{if(files.has(path))return {error:{code:'exists'}};files.set(path,new Uint8Array(bytes));return lost?{error:{code:'network'}}:{data:{path}};},download:async path=>{if(expireAfterDownload)rows.get('photo').expiresAt='2000-01-01T00:00:00Z';if(revokedAfterDownload)allowed=false;return files.has(path)?{data:new Blob([files.get(path)])}:{error:{code:'not_found',statusCode:404}};},remove:async paths=>{paths.forEach(p=>files.delete(p));return {data:[]};}};
 const store={find:async id=>rows.get(id),reserve:async r=>{const old=rows.get(r.evidenceId);if(old)return old;const record={...r,confirmed:false,expiresAt:'2099-01-01T00:00Z'};rows.set(r.evidenceId,record);return record;},confirm:async r=>{await authorize();Object.assign(rows.get(r.evidenceId),r,{confirmed:true});},revoke:async id=>{const r=rows.get(id);if(r)r.revoked=true;return r;}};
 const p=createRemotePhotoProvider({supabase:{storage:{from:name=>{assert.equal(name,'remote-weighin-evidence');return bucket;}}},authorize,verifyCapture:async()=>{},normalizeJPEG,evidenceStore:store});
 const input={evidenceId:'photo',binding:{programId:'program',captureId:'capture',operatorId:'coach'},jpeg};
 return {p,input,files,rows,setAllowed:x=>allowed=x,lost:()=>lost=true,expireOnDownload:()=>expireAfterDownload=true,revokeOnDownload:()=>revokedAfterDownload=true};}
test('private photo upload/read returns bytes and no-cache headers, no URL',async()=>{const f=fixture();await f.p.upload('s',f.input);const r=await f.p.read('s','photo');assert.deepEqual(r.bytes,normalizeJPEG(f.input.jpeg));assert.equal(r.headers['Cache-Control'],'no-store, private');assert.equal(r.url,undefined);});
test('lost upload acknowledgment verifies stored digest before confirming',async()=>{const f=fixture();f.lost();await f.p.upload('s',f.input);assert.equal(f.files.size,1);assert.equal(f.rows.get('photo').confirmed,true);});
test('same evidence ID cannot substitute changed photo',async()=>{const f=fixture();await f.p.upload('s',f.input);await assert.rejects(f.p.upload('s',{...f.input,jpeg:codec.encode({width:4,height:4,data:new Uint8Array(64).fill(10)},80).data}),/conflict/);});
test('bad JPEG and path injection rejected before write',async()=>{const f=fixture();await assert.rejects(f.p.upload('s',{...f.input,evidenceId:'../photo'}),/JPEG/);await assert.rejects(f.p.upload('s',{...f.input,jpeg:new Uint8Array([1,2,3,4])}),/JPEG/);assert.equal(f.files.size,0);});
test('revocation before/after download denies read',async()=>{const f=fixture();await f.p.upload('s',f.input);f.setAllowed(false);await assert.rejects(f.p.read('s','photo'),/Revoked/);f.setAllowed(true);f.revokeOnDownload();await assert.rejects(f.p.read('s','photo'),/Revoked/);});
test('tampered stored photo fails integrity',async()=>{const f=fixture();await f.p.upload('s',f.input);f.files.set(f.rows.get('photo').path,new Uint8Array([255,216,0,255,217]));await assert.rejects(f.p.read('s','photo'),/integrity/);});
test('purge revokes evidence and verifies object absence',async()=>{const f=fixture();await f.p.upload('s',f.input);assert.deepEqual(await f.p.purge('photo'),{removed:true});assert.equal(f.files.size,0);await assert.rejects(f.p.read('s','photo'),/unavailable/);});

test('photo expiry while download is in flight denies the response',async()=>{const f=fixture();await f.p.upload('s',f.input);f.expireOnDownload();await assert.rejects(f.p.read('s','photo'),/unavailable/);});

test('valid marker envelope with invalid image data never reaches private storage',async()=>{const f=fixture();await assert.rejects(f.p.upload('s',{...f.input,jpeg:new Uint8Array([255,216,255,217])}),/JPEG/);assert.equal(f.files.size,0);assert.equal(f.rows.size,0);});
