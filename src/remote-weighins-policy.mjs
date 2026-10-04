// Calendar eligibility uses the event zone; retention uses elapsed time.
export const REMOTE_RETENTION_MS = 10 * 24 * 60 * 60 * 1000;
export function remoteExpiresAt(binding) {
 const captured = Date.parse(binding.capturedAt);
 if (!Number.isFinite(captured)) throw Error('Valid original capture time required');
 return new Date(captured + REMOTE_RETENTION_MS).toISOString();
}
export function eventCaptureWindow({eventDate,timeZone}) {
 if (!/^\d{4}-\d{2}-\d{2}$/.test(eventDate)) throw Error('Valid event date required');
 const base=Date.parse(eventDate+'T00:00:00Z');
 if(!Number.isFinite(base)||new Date(base).toISOString().slice(0,10)!==eventDate) throw Error('Valid event date required');
 const formatter=new Intl.DateTimeFormat('en-CA',{timeZone,year:'numeric',month:'2-digit',day:'2-digit'});
 const dateAt=t=>{const p=Object.fromEntries(formatter.formatToParts(t).map(x=>[x.type,x.value]));return `${p.year}-${p.month}-${p.day}`;};
 const boundary=day=>{
  const nominal=Date.parse(day+'T00:00:00Z');let lo=nominal-48*3600000,hi=nominal+48*3600000;
  while(lo<hi){const mid=Math.floor((lo+hi)/2);if(dateAt(mid)<day)lo=mid+1;else hi=mid;}
  if(dateAt(lo)!==day)throw Error('Event calendar date unavailable in this time zone');
  return new Date(lo).toISOString();
 };
 const day=offset=>new Date(base+offset*86400000).toISOString().slice(0,10);
 return Object.freeze({eventDate,timeZone,opensAt:boundary(day(-1)),closesAt:boundary(day(1))});
}
