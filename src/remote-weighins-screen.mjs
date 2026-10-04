// In-app screen component. App coordinator supplies authorized windows and scoped API.
// This component is not registered/enabled by production index.html yet.
import {collectRemoteExport} from './remote-weighins-export.mjs';
import {remoteReviewWorkbook} from './remote-weighins-xlsx.mjs';
export function mountRemoteReportingScreen({root,scope,windows,api,isCurrent,document=root?.ownerDocument}) {
 if(!root||!document||!Array.isArray(windows)||![api?.report,api?.photo,isCurrent].every(f=>typeof f==='function')||!scope?.programId)throw Error('Authorized reporting screen dependencies required');
 let active=true,epoch=0,nextOffset=null,selected=null,revision=null,objectURL=null,photoEpoch=0;
 const current=t=>active&&t===epoch&&isCurrent(scope)===true;
 const node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=String(text);return n;};
 const closePhoto=()=>{photoEpoch++;if(objectURL){URL.revokeObjectURL(objectURL);objectURL=null;}photoBox.replaceChildren();};
 const section=node('section');section.className='remote-reporting-screen';
 const title=node('h2','Remote weigh-ins'),description=node('p','Review accepted club reports. Captured time and server receipt time are shown separately.');
 const retention=node('p','After weigh-ins, download a copy for your records. Online weights and verification photos are deleted 10 days after capture. Your downloaded spreadsheet remains available after the online copy expires.');
 const setupNotice=node('p','Camera setup: place the scale on a firm, level floor and secure the device far enough away to show the athlete’s face, singlet, both feet and scale. Take a setup test photo before starting. Use a private area with nobody else in frame; recheck after moving the device or scale.');setupNotice.hidden=scope.canCapture!==true;
 const filters=node('div');filters.className='ops-actions';
 const windowSelect=node('select');windowSelect.setAttribute('aria-label','Reporting window');
 for(const w of windows){if(w.programId!==scope.programId)throw Error('Reporting window scope mismatch');const option=node('option',w.label||w.id);option.value=w.id;windowSelect.append(option);}
 const statusSelect=node('select');statusSelect.setAttribute('aria-label','Submission status');
 for(const [value,label] of [['','All statuses'],['submitted','Submitted'],['late','Late'],['missing','Missing']]){const option=node('option',label);option.value=value;statusSelect.append(option);}
 const refresh=node('button','Refresh');refresh.type='button';
 const capture=node('button','Start club weigh-ins');capture.type='button';capture.hidden=scope.canCapture!==true||typeof api.captureWindow!=='function';
 const exportButton=node('button','Download spreadsheet CSV');exportButton.type='button';
 const workbookButton=node('button','Download Excel with photos');workbookButton.type='button';
 filters.append(windowSelect,statusSelect,refresh,capture,exportButton,workbookButton);
 const message=node('p');message.setAttribute('role','status');message.setAttribute('aria-live','polite');
 const deadline=node('p'),counts=node('p'),table=node('table'),head=node('thead'),header=node('tr'),rows=node('tbody');
 deadline.setAttribute('aria-label','Allotted weigh-in period');
 for(const label of ['Athlete','Club','USAW ID','AAU number','Status','Weight','Captured','Received','Photo'])header.append(node('th',label));head.append(header);table.append(head,rows);
 const wrap=node('div');wrap.style.overflowX='auto';wrap.append(table);
 const more=node('button','Load more');more.type='button';more.hidden=true;
 const photoBox=node('div');photoBox.setAttribute('aria-label','Private verification photo');
 section.append(title,description,retention,setupNotice,filters,deadline,message,counts,wrap,more,photoBox);root.replaceChildren(section);
 const query=offset=>({programId:scope.programId,windowId:windowSelect.value,clubId:scope.clubId??null,status:statusSelect.value||null,offset,limit:100,revision:offset?revision:null});
 const fmt=(value,timeZone)=>new Intl.DateTimeFormat('en-US',{timeZone,month:'short',day:'numeric',hour:'numeric',minute:'2-digit',timeZoneName:'short'}).format(new Date(value));
 async function showPhoto(submissionId){
  const t=epoch;closePhoto();const photoTicket=photoEpoch;message.textContent='Opening private verification photo…';
  try{const blob=await api.photo({submissionId});if(!current(t)||photoTicket!==photoEpoch)return;if(!(blob instanceof Blob)||blob.type!=='image/jpeg'||blob.size>5*1024*1024)throw Error('Photo unavailable');
   objectURL=URL.createObjectURL(blob);const image=node('img');image.src=objectURL;image.alt='Verification snapshot from this weigh-in';image.style.maxWidth='100%';
   const hide=node('button','Close photo');hide.type='button';hide.onclick=closePhoto;photoBox.append(hide,image);message.textContent='Private photo open. Use it as a visual review aid.';
  }catch{if(current(t)&&photoTicket===photoEpoch)message.textContent='Photo could not be opened. Check your access and try again.';}
 }
 async function load(append=false){
  if(!active||!isCurrent(scope)){close();return;}
  const offset=append?nextOffset:0;if(offset===null)return;
  const t=++epoch;closePhoto();message.textContent='Loading accepted reports…';refresh.disabled=true;more.disabled=true;capture.disabled=true;
  if(!append){rows.replaceChildren();counts.textContent='';nextOffset=null;revision=null;more.hidden=true;}
  try{const request=query(offset),report=await api.report(request);if(!current(t))return;
   if(report.programId!==scope.programId||report.windowId!==request.windowId||!Array.isArray(report.rows)||typeof report.revision!=='string'||!/^[a-f0-9]{64}$/.test(report.revision)||(append&&report.revision!==revision))throw Error('Report scope changed');
   revision=report.revision;
   for(const row of report.rows){
    if(scope.clubId&&row.clubId!==scope.clubId)throw Error('Report club changed');
    const prior=rows.lastElementChild;
    if(!prior||prior.dataset.clubId!==row.clubId){const group=node('tr');group.dataset.clubId=row.clubId;const cell=node('th',row.clubName);cell.colSpan=9;cell.scope='rowgroup';group.append(cell);rows.append(group);}
    const tr=node('tr');tr.dataset.clubId=row.clubId;tr.dataset.athleteRow='true';tr.append(node('td',row.athleteName),node('td',row.clubName),node('td',row.usawId||'—'),node('td',row.aauNumber||'—'),node('td',row.status));
    tr.append(node('td',row.submission?`${Number(row.submission.weight).toFixed(1)} lb`:'—'));
    tr.append(node('td',row.submission?fmt(row.submission.capturedAt,report.timeZone):'—'),node('td',row.submission?fmt(row.submission.receivedAt,report.timeZone):'—'));
    const cell=node('td');if(row.submission){const button=node('button','View photo');button.type='button';button.onclick=()=>showPhoto(row.submission.submissionId);cell.append(button);}tr.append(cell);rows.append(tr);
   }
   selected=windows.find(w=>w.id===request.windowId);nextOffset=report.nextOffset;more.hidden=nextOffset===null;
   deadline.textContent=selected?.opensAt&&selected?.closesAt?`Allotted weigh-in period: ${fmt(selected.opensAt,report.timeZone)} until ${fmt(selected.closesAt,report.timeZone)}. New captures must finish before the closing time. Capture timestamps are locked; later uploads keep the original time. ${selected.allowReweigh===true?'Reweighs are allowed: one result per athlete uses the lowest valid weight with its matching verification photo.':'One accepted attempt per athlete; reweighs are not enabled.'}`:'';
   counts.textContent=`Expected: ${report.counts.expected} · Submitted: ${report.counts.submitted} · Late: ${report.counts.late} · Missing: ${report.counts.missing}`;
   title.textContent=report.classification||'Remote weigh-ins';message.textContent=`${rows.querySelectorAll('[data-athlete-row]').length} of ${report.total} athletes shown. Times: ${report.timeZone}. Pending device uploads are not counted as submitted.`;
  }catch{if(current(t)){rows.replaceChildren();counts.textContent='';more.hidden=true;nextOffset=null;message.textContent='Reports could not be loaded. Check your access and retry.';}}
  finally{if(current(t)){refresh.disabled=false;more.disabled=false;capture.disabled=false;}}
 }
 windowSelect.onchange=()=>load();statusSelect.onchange=()=>load();refresh.onclick=()=>load();more.onclick=()=>load(true);
 const download=async withPhotos=>{const t=epoch;exportButton.disabled=true;workbookButton.disabled=true;message.textContent='Preparing all matching athletes for export…';let url;
  try{const result=await collectRemoteExport({api,query:query(0),isCurrent:()=>current(t)});if(!current(t))return;
   const blob=withPhotos?await remoteReviewWorkbook({rows:result.rows,api,isCurrent:()=>current(t)}):new Blob(['\ufeff',result.csv],{type:'text/csv;charset=utf-8'});if(!current(t))return;
   await result.validate();if(!current(t))return;
   url=URL.createObjectURL(blob);const link=node('a');link.href=url;link.download=withPhotos?'remote-weighins.xlsx':'remote-weighins.csv';section.append(link);link.click();link.remove();message.textContent='Spreadsheet downloaded. Keep your copy for your records. Online weights and photos expire 10 days after capture; your saved spreadsheet remains available.';
  }catch{if(current(t))message.textContent='Export failed. Refresh and retry, or export one club at a time.';}finally{if(url)URL.revokeObjectURL(url);exportButton.disabled=false;workbookButton.disabled=false;}
 };
 exportButton.onclick=()=>download(false);workbookButton.onclick=()=>download(true);
 capture.onclick=async()=>{const t=epoch;if(!current(t)||!selected)return;capture.disabled=true;try{await api.captureWindow(selected);if(current(t))message.textContent='Club capture opened. Saved uploads remain pending until accepted by the server.';}catch{if(current(t))message.textContent='Capture could not open. Check club access, scale and camera permissions.';}finally{if(current(t))capture.disabled=false;}};
 function close(){active=false;epoch++;closePhoto();root.replaceChildren();}
 const ready=windows.length?load():Promise.resolve().then(()=>{message.textContent='No authorized reporting windows are available.';capture.disabled=true;});
 return Object.freeze({ready,refresh:()=>load(),close});
}

export function mountRemoteReportingHome({root,api,isCurrent,document=root?.ownerDocument}) {
 let active=true,screen=null,scopes=[];
 const host=document.createElement('section'),label=document.createElement('label'),select=document.createElement('select'),status=document.createElement('p'),content=document.createElement('div');
 label.textContent='Reporting program and club';label.append(select);status.setAttribute('role','status');status.textContent='Checking reporting access…';host.append(label,status,content);root.replaceChildren(host);
 function close(){active=false;screen?.close();root.replaceChildren();}
 function open(){screen?.close();const scope=scopes[Number(select.value)];if(!active||!scope||!isCurrent(scope)){close();return;}
  screen=mountRemoteReportingScreen({root:content,scope,windows:scope.windows,api:{...api,captureWindow:api.captureWindow?(window=>api.captureWindow({scope,window})):undefined},isCurrent,document});
 }
 select.onchange=open;
 const ready=(async()=>{try{const result=await api.context();if(!active)return;scopes=result.scopes;if(!Array.isArray(scopes))throw Error('Invalid context');
  select.replaceChildren(...scopes.map((scope,i)=>{const option=document.createElement('option');option.value=String(i);option.textContent=scope.label;return option;}));
  status.textContent=scopes.length?'Choose an authorized club or network report.':'No remote reporting assignment is available for this account.';select.disabled=!scopes.length;if(scopes.length)open();
 }catch{if(active){status.textContent='Reporting access could not be checked. Close and retry.';select.disabled=true;}}})();
 return Object.freeze({ready,close});
}
