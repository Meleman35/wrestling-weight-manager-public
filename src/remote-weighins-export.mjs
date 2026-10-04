import {reportCsv} from './remote-weighins.mjs';
// All pages pass through the authorized report API. Never export just the visible
// page or bypass the API to query arbitrary athlete records.
export async function collectRemoteExport({api,query,isCurrent,maxRows=20000}) {
 if(![api?.report,isCurrent].every(f=>typeof f==='function'))throw Error('Authorized export required');
 const rows=[],seen=new Set();let offset=0,total=null;
 do {
  if(!isCurrent())throw Error('Export session closed');
  const report=await api.report({...query,offset,limit:500,format:'json'});
  if(!isCurrent()||report.programId!==query.programId||report.windowId!==query.windowId||!Array.isArray(report.rows)||!Number.isInteger(report.total)||report.total<0||report.total>maxRows)throw Error('Export scope changed');
  if(total!==null&&report.total!==total)throw Error('Report changed; refresh and export again');total=report.total;
  for(const row of report.rows){if(query.clubId&&row.clubId!==query.clubId)throw Error('Export club changed');const key=JSON.stringify([row.clubId,row.athleteId]);if(seen.has(key))throw Error('Report changed; refresh and export again');seen.add(key);rows.push(row);}
  if(rows.length>maxRows)throw Error('Export too large');
  if(report.nextOffset!==null&&(!Number.isInteger(report.nextOffset)||report.nextOffset!==offset+report.rows.length||report.nextOffset<=offset))throw Error('Invalid export pagination');
  offset=report.nextOffset;
 }while(offset!==null);
 if(rows.length!==total)throw Error('Incomplete report; retry export');
 return {rows,csv:reportCsv(rows)};
}
