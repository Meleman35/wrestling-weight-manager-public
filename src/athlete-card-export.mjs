// Uses the existing authorized card loader. Never rotates a credential.
export async function collectAthleteCards({roster, selectedIDs, loadCard, isCurrent, onProgress = () => {}}) {
  if (!Array.isArray(roster) || !Array.isArray(selectedIDs) || !selectedIDs.length)
    throw Error('Select at least one athlete.');
  const allowed = new Set(roster.map(row => String(row.athlete_id)));
  const ids = [...new Set(selectedIDs.map(String))];
  if(ids.length>500)throw Error('Select up to 500 athletes per export.');
  if (ids.some(id => !allowed.has(id))) throw Error('An athlete is no longer in the available roster.');
  const cards = [];
  for (const id of ids) {
    if (!isCurrent()) throw Error('The team or account changed. Start the export again.');
    const card = await loadCard(id, false);
    if (!isCurrent()) throw Error('The team or account changed. Start the export again.');
    if (!card || String(card.athlete_id) !== id || typeof card.credential_token !== 'string' || !card.credential_token)
      throw Error('An athlete card could not be verified. No file was exported.');
    cards.push(Object.freeze({...card}));
    onProgress(cards.length, ids.length);
  }
  return Object.freeze(cards);
}

// CR80: 85.60 x 53.98 mm. Letter sheet fits eight with cutting space.
export function athleteCardLayout(count, individual = false) {
  if (!Number.isInteger(count) || count < 1) throw Error('No cards to export.');
  const mm = 72 / 25.4, width = 85.6 * mm, height = 53.98 * mm;
  return Array.from({length:count}, (_,i) => ({
    page: individual ? i : Math.floor(i / 8),
    pageWidth: individual ? width : 612,
    pageHeight: individual ? height : 792,
    x: individual ? 0 : (612 - 2 * width - 18) / 2 + (i % 2) * (width + 18),
    y: individual ? 0 : 792 - 45 - height - Math.floor((i % 8) / 2) * (height + 18),
    width, height
  }));
}

export async function renderAthleteCardPDF({cards, teamName, individual = false,
  PDFLib, document, QRCode, isCurrent, loadPhoto = async () => null}) {
  const pdf = await PDFLib.PDFDocument.create();
  pdf.setTitle(String(teamName || 'Team') + ' - Athlete Cards');
  const positions = athleteCardLayout(cards.length, individual);
  let page, pageIndex = -1;
  for (let i=0; i<cards.length; i++) {
    if (!isCurrent()) throw Error('The team or account changed. Start the export again.');
    const c=cards[i], p=positions[i];
    if (p.page !== pageIndex) { page=pdf.addPage([p.pageWidth,p.pageHeight]);pageIndex=p.page; }
    const canvas=document.createElement('canvas');canvas.width=1011;canvas.height=638;
    const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,1011,638);
    ctx.fillStyle='#153b75';ctx.fillRect(0,0,1011,88);
    ctx.fillStyle='#fff';ctx.font='bold 32px sans-serif';ctx.fillText('WRESTLING MANAGER',34,57);
    ctx.fillStyle='#14253b';ctx.font='bold 43px sans-serif';
    const name=[c.first_name,c.last_name].filter(Boolean).join(' ');
    ctx.fillText(name,34,160,560);ctx.font='28px sans-serif';ctx.fillText(String(teamName||''),34,215,550);
    ctx.font='26px sans-serif';ctx.fillText('Athlete check-in card',34,270);
    const photo = c.photo_path ? await loadPhoto(c.photo_path) : null;
    if (!isCurrent()) throw Error('The team or account changed. Start the export again.');
    ctx.fillStyle='#edf2f8';ctx.fillRect(34,300,180,180);
    if(photo){const size=Math.min(photo.naturalWidth,photo.naturalHeight);ctx.drawImage(photo,(photo.naturalWidth-size)/2,(photo.naturalHeight-size)/2,size,size,34,300,180,180);}
    else {ctx.fillStyle='#153b75';ctx.font='bold 55px sans-serif';ctx.fillText([c.first_name,c.last_name].filter(Boolean).map(x=>Array.from(x)[0]).join(''),65,410,125);}
    ctx.fillStyle='#14253b';ctx.font='26px sans-serif';
    ctx.fillText('Keep this card private.',34,540);
    ctx.fillText('NFC must be programmed separately.',34,585,590);
    const qrBox=document.createElement('div');
    new QRCode(qrBox,{text:c.credential_token,width:320,height:320,correctLevel:QRCode.CorrectLevel.M});
    const qr=qrBox.querySelector('canvas');if(!qr)throw Error('QR code could not be generated.');
    // White quiet zone remains outside the code on all four sides.
    ctx.imageSmoothingEnabled=false;ctx.drawImage(qr,650,170,320,320);
    const png=await pdf.embedPng(canvas.toDataURL('image/png'));
    if (!isCurrent()) throw Error('The team or account changed. Start the export again.');
    page.drawImage(png,{x:p.x,y:p.y,width:p.width,height:p.height});
    if(!individual)page.drawRectangle({x:p.x,y:p.y,width:p.width,height:p.height,
      borderColor:PDFLib.rgb(.65,.65,.65),borderWidth:.4});
    canvas.width=canvas.height=0;qrBox.replaceChildren();
  }
  const bytes=await pdf.save();
  if(!isCurrent())throw Error('The team or account changed. Start the export again.');
  return bytes;
}
