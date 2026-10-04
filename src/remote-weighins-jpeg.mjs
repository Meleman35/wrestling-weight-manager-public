// Server-only normalization. Supply the pinned jpeg-js 0.4.4 codec in the
// request runtime; do not use a browser image element or trust JPEG markers.
const maxBytes=5*1024*1024,maxDimension=1280;
const invalid=()=>{throw Error('A complete bounded JPEG capture is required');};
function dimensions(bytes){
 if(!(bytes instanceof Uint8Array)||bytes.length<4||bytes.length>maxBytes||bytes[0]!==255||bytes[1]!==216||bytes.at(-2)!==255||bytes.at(-1)!==217)invalid();
 let at=2,frame=null,segments=0;
 while(at<bytes.length-2){
  if(++segments>1024||bytes[at++]!==255)invalid();
  while(bytes[at]===255)at++;
  const marker=bytes[at++];
  if(marker===0xda){if(!frame)invalid();return frame;}
  if(marker===0xd8||marker===0xd9||marker===0||marker===1||(marker>=0xd0&&marker<=0xd7)||at+2>bytes.length)invalid();
  const length=bytes[at]*256+bytes[at+1];
  if(length<2||at+length>bytes.length-2)invalid();
  if(marker>=0xc0&&marker<=0xcf&&![0xc4,0xc8,0xcc].includes(marker)){
   if(frame||![0xc0,0xc2].includes(marker)||length<8||bytes[at+2]!==8)invalid();
   const height=bytes[at+3]*256+bytes[at+4],width=bytes[at+5]*256+bytes[at+6],components=bytes[at+7];
   if(!width||!height||width>maxDimension||height>maxDimension||![1,3].includes(components)||length!==8+3*components)invalid();
   frame={width,height};
  }
  at+=length;
 }
 invalid();
}
export function createRemoteJPEGNormalizer({codec}){
 if(typeof codec?.decode!=='function'||typeof codec?.encode!=='function')throw Error('Trusted JPEG codec required');
 return jpeg=>{
  const expected=dimensions(jpeg);
  try{
   const decoded=codec.decode(jpeg,{useTArray:true,formatAsRGBA:true,tolerantDecoding:false,maxResolutionInMP:1.6384,maxMemoryUsageInMB:32});
   if(decoded.width!==expected.width||decoded.height!==expected.height||!(decoded.data instanceof Uint8Array)||decoded.data.length!==expected.width*expected.height*4)invalid();
   // The native camera already renders upright pixels. Keep the whole frame,
   // and pass only pixels/dimensions so EXIF, comments and source profiles do
   // not survive the trusted server encode. Pin codec/quality for stable retries.
   const output=codec.encode({width:decoded.width,height:decoded.height,data:decoded.data},80).data;
   const actual=dimensions(output);
   if(actual.width!==expected.width||actual.height!==expected.height)invalid();
   return new Uint8Array(output);
  }catch{invalid();}
 };
}
