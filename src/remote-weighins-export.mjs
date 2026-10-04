import {reportCsv} from './remote-weighins.mjs';
// All pages pass through the authorized report API. Never export just the visible
// page or bypass the API to query arbitrary athlete records.
export async function collectRemoteExport({api,query,isCurrent,maxRows=20000}) {
 if(![api?.report,isCurrent].every(f=>typeof f==='function'))throw Error('Authorized export required');
 const scope=Object.freeze({...query}),rows=[],seen=new Set();let offset=0,total=null,revision=null;
 do {
  if(!isCurrent())throw Error('Export session closed');
  const report=await api.report({...scope,offset,limit:500,format:'json',revision});
  if(!isCurrent()||report.programId!==scope.programId||report.windowId!==scope.windowId||!Array.isArray(report.rows)||!Number.isInteger(report.total)||report.total<0||report.total>maxRows||typeof report.revision!=='string'||!/^[a-f0-9]{64}$/.test(report.revision))throw Error('Export scope changed');
  if(revision!==null&&report.revision!==revision)throw Error('Report changed; refresh and export again');revision=report.revision;
  if(total!==null&&report.total!==total)throw Error('Report changed; refresh and export again');total=report.total;
  for(const row of report.rows){if(scope.clubId&&row.clubId!==scope.clubId)throw Error('Export club changed');const key=JSON.stringify([row.clubId,row.athleteId]);if(seen.has(key))throw Error('Report changed; refresh and export again');seen.add(key);rows.push(row);}
  if(rows.length>maxRows)throw Error('Export too large');
  if(report.nextOffset!==null&&(!Number.isInteger(report.nextOffset)||report.nextOffset!==offset+report.rows.length||report.nextOffset<=offset))throw Error('Invalid export pagination');
  offset=report.nextOffset;
 }while(offset!==null);
 if(rows.length!==total)throw Error('Incomplete report; retry export');
 const validate=async()=>{
  if(!isCurrent())throw Error('Export session closed');
  const latest=await api.report({...scope,offset:0,limit:1,format:'json',revision});
  if(!isCurrent()||latest.programId!==scope.programId||latest.windowId!==scope.windowId||latest.revision!==revision||latest.total!==total)throw Error('Report changed; refresh and export again');
 };
 await validate();
 return {rows,csv:reportCsv(rows),revision,validate};
}
