// Dependency-free OOXML workbook, with inline text cells and embedded JPEGs.
const enc=new TextEncoder(),xml=x=>String(x??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const crc=bytes=>{let c=0xffffffff;for(const b of bytes){c^=b;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;};
function zip(files){const chunks=[],central=[];let offset=0;
 for(const [name,data] of files){const n=enc.encode(name),b=typeof data==='string'?enc.encode(data):data,c=crc(b),h=new Uint8Array(30+n.length),v=new DataView(h.buffer);v.setUint32(0,0x04034b50,true);v.setUint16(4,20,true);v.setUint32(14,c,true);v.setUint32(18,b.length,true);v.setUint32(22,b.length,true);v.setUint16(26,n.length,true);h.set(n,30);chunks.push(h,b);
 const ch=new Uint8Array(46+n.length),cv=new DataView(ch.buffer);cv.setUint32(0,0x02014b50,true);cv.setUint16(4,20,true);cv.setUint16(6,20,true);cv.setUint32(16,c,true);cv.setUint32(20,b.length,true);cv.setUint32(24,b.length,true);cv.setUint16(28,n.length,true);cv.setUint32(42,offset,true);ch.set(n,46);central.push(ch);offset+=h.length+b.length;}
 const size=central.reduce((n,b)=>n+b.length,0),end=new Uint8Array(22),v=new DataView(end.buffer);v.setUint32(0,0x06054b50,true);v.setUint16(8,files.length,true);v.setUint16(10,files.length,true);v.setUint32(12,size,true);v.setUint32(16,offset,true);const out=new Uint8Array(offset+size+22);let p=0;for(const b of [...chunks,...central,end]){out.set(b,p);p+=b.length;}return out;
}
const decl='<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const rels=entries=>decl+'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+entries.map(([id,type,target])=>`<Relationship Id="${id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/${type}" Target="${target}"/>`).join('')+'</Relationships>';
// Read dimensions for aspect-fit placement only. The server must still fully
// decode/validate evidence; a JPEG header is not proof of a valid image.
function jpegDimensions(bytes) {
 if(bytes.length<4||bytes[0]!==255||bytes[1]!==216||bytes.at(-2)!==255||bytes.at(-1)!==217)throw Error('Invalid JPEG');
 let p=2;
 while(p+4<=bytes.length){
  if(bytes[p++]!==255)throw Error('Invalid JPEG segment');
  while(bytes[p]===255)p++;
  const marker=bytes[p++];
  if(marker===0xda||marker===0xd9)break;
  if(marker===0x01||(marker>=0xd0&&marker<=0xd7))continue;
  const size=(bytes[p]<<8)|bytes[p+1];if(size<2||p+size>bytes.length)throw Error('Invalid JPEG segment');
  if([0xc0,0xc1,0xc2].includes(marker)){
   if(size<8)throw Error('Invalid JPEG dimensions');
   const height=(bytes[p+3]<<8)|bytes[p+4],width=(bytes[p+5]<<8)|bytes[p+6];
   if(!width||!height||width>8192||height>8192||width*height>16000000)throw Error('Invalid JPEG dimensions');
   return {width,height};
  }
  p+=size;
 }
 throw Error('JPEG dimensions unavailable');
}
export async function remoteReviewWorkbook({rows,api,isCurrent,maxPhotoBytes=50*1024*1024}) {
 if(!Array.isArray(rows)||rows.length>20000||typeof api?.photo!=='function'||typeof isCurrent!=='function')throw Error('Authorized workbook dependencies required');
 const files=[],images=[];let bytes=0;
 const headers=['Club','Athlete','First name','Last name','USAW ID','AAU number','Status','Scale weight (lb)','Captured at','Received at','Verification submission ID','Expires at','Verification photo'];
 const all=[headers,...rows.map(r=>[r.clubName,r.athleteName,r.firstName,r.lastName,r.usawId,r.aauNumber,r.status,r.submission?.weight,r.submission?.capturedAt,r.submission?.receivedAt,r.submission?.submissionId,r.submission?new Date(Date.parse(r.submission.capturedAt)+240*3600000).toISOString():'',''])];
 for(let i=0;i<rows.length;i++){if(!isCurrent())throw Error('Export session closed');const r=rows[i];if(!r.submission)continue;
  const photo=await api.photo({submissionId:r.submission.submissionId});if(!isCurrent())throw Error('Export session closed');if(!(photo instanceof Blob)||photo.type!=='image/jpeg'||photo.size>5*1024*1024)throw Error('Verification photo unavailable');
  bytes+=photo.size;if(bytes>maxPhotoBytes)throw Error('Workbook photos too large; export one club at a time');
  const image=new Uint8Array(await photo.arrayBuffer());if(!isCurrent())throw Error('Export session closed');const {width,height}=jpegDimensions(image);const factor=Math.min(160/width,180/height);const cx=Math.round(width*factor*9525),cy=Math.round(height*factor*9525);
  const n=images.length+1;images.push({n,row:i+1,cx,cy});files.push([`xl/media/image${n}.jpeg`,image]);
 }
 const sheet=decl+'<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="7" width="24" customWidth="1"/><col min="8" max="8" width="18" customWidth="1"/><col min="9" max="12" width="28" customWidth="1"/><col min="13" max="13" width="23" customWidth="1"/></cols><sheetData>'+all.map((r,i)=>`<row r="${i+1}" ht="${i?(rows[i-1].submission?144:25):25}" customHeight="1">`+r.map((v,j)=>typeof v==='number'?`<c r="${String.fromCharCode(65+j)}${i+1}"><v>${v}</v></c>`:`<c r="${String.fromCharCode(65+j)}${i+1}" t="inlineStr"><is><t xml:space="preserve">${xml(v)}</t></is></c>`).join('')+'</row>').join('')+'</sheetData>'+`<autoFilter ref="A1:M${all.length}"/>`+(images.length?'<drawing r:id="drawing"/>':'')+'</worksheet>';
 files.push(['xl/worksheets/sheet1.xml',sheet],['xl/workbook.xml',decl+'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Club weigh-ins" sheetId="1" r:id="sheet"/></sheets></workbook>'],['xl/_rels/workbook.xml.rels',rels([['sheet','worksheet','worksheets/sheet1.xml']])],['_rels/.rels',rels([['workbook','officeDocument','xl/workbook.xml']])]);
 if(images.length){files.push(['xl/worksheets/_rels/sheet1.xml.rels',rels([['drawing','drawing','../drawings/drawing1.xml']])],['xl/drawings/_rels/drawing1.xml.rels',rels(images.map(({n})=>[`image${n}`,'image',`../media/image${n}.jpeg`]))],['xl/drawings/drawing1.xml',decl+'<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'+images.map(({n,row,cx,cy})=>`<xdr:oneCellAnchor><xdr:from><xdr:col>12</xdr:col><xdr:colOff>28575</xdr:colOff><xdr:row>${row}</xdr:row><xdr:rowOff>28575</xdr:rowOff></xdr:from><xdr:ext cx="${cx}" cy="${cy}"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="${n}" name="Verification ${n}"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="image${n}"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor>`).join('')+'</xdr:wsDr>']);}
 files.push(['[Content_Types].xml',decl+'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpeg" ContentType="image/jpeg"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'+(images.length?'<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>':'')+'</Types>']);
 if(!isCurrent())throw Error('Export session closed');return new Blob([zip(files)],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
}
