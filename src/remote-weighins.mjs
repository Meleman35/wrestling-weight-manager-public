/* Remote-only capture contract. Not loaded by production index.html.
 * Adapters must enforce server authorization, coverage and evidence ownership.
 * Client timestamps/evidence are not identity or certified-weight proof. */
const fail = message => { throw new Error(message); };
const id = value => typeof value === 'string' && value.length > 0 && value.length <= 160;
const instant = value => {
  const n = Date.parse(value);
  if (!Number.isFinite(n)) fail('Invalid timestamp');
  return n;
};
export function validateWindow(window) {
  if (!id(window?.id) || !id(window.programId)) fail('Reporting window required');
  try { new Intl.DateTimeFormat('en', {timeZone: window.timeZone}); }
  catch { fail('Reporting timezone required'); }
  if (!window.timeZone || instant(window.opensAt) >= instant(window.closesAt)) fail('Invalid reporting window');
  if(window.allowReweigh!==undefined&&typeof window.allowReweigh!=='boolean')fail('Invalid repeat weigh-in setting');
  return Object.freeze({...window});
}
export function createRemoteCapture({context, window, now = Date.now, uuid = () => crypto.randomUUID(), submit, maxAgeMs = 30000}) {
  const period = validateWindow(window);
  if (![context?.accountId, context?.clubId, context?.generation].every(id) || typeof submit !== 'function') fail('Authorized capture adapter required');
  if (!Number.isFinite(maxAgeMs) || maxAgeMs < 1000 || maxAgeMs > 30000) fail('Invalid evidence freshness limit');
  const owner = Object.freeze({...context});
  let active = true, pending = null, busy = false;
  const requireActive = () => { if (!active) fail('Capture closed'); };
  const inWindow = time => time >= instant(period.opensAt) && time < instant(period.closesAt);
  const validToken = token => { requireActive(); if (!pending || token !== pending.token) fail('Capture changed; scan again'); };
  const fresh = stamp => {
    const elapsed = now() - stamp;
    if (!Number.isFinite(elapsed) || elapsed < 0 || elapsed > maxAgeMs) fail('Evidence expired; retake the reading and photo');
  };
  function state() {
    return Object.freeze({phase: !active ? 'closed' : busy ? 'submitting' : pending?.receipt ? 'submitted' : pending?.payload ? 'pending_retry' : !pending ? 'scan' : !pending.weight ? 'weight' : !pending.photo ? 'photo' : 'ready', athleteId: pending?.athleteId ?? null, submissionId: pending?.payload?.submissionId ?? null});
  }
  return Object.freeze({
    state,
    scan(athleteId, method) {
      requireActive(); if (busy || pending?.payload) fail('Finish or discard the pending submission before scanning');
      if (!id(athleteId) || !['qr','nfc'].includes(method)) fail('Scan a valid QR or NFC credential');
      const started = now(); if (!inWindow(started)) fail('Reporting window is closed');
      pending = {token: uuid(), athleteId, method, started, weight: null, photo: null, payload: null, receipt: null};
      return pending.token;
    },
    reading(token, {value, unit, settled, source, observedAt}) {
      validToken(token); if (busy || pending.payload) fail('Submission is frozen');
      if (source !== 'scale' || settled !== true || unit !== 'lb' || !Number.isFinite(value) || value <= 0 || value > 800) fail('A fresh settled scale reading in pounds is required');
      if (!Number.isFinite(observedAt) || observedAt <= pending.started) fail('Reading predates this scan');
      if (!inWindow(observedAt)) fail('Reporting window is closed');
      fresh(observedAt); pending.weight = {value, unit, observedAt}; pending.photo = null;
    },
    snapshot(token, {evidenceId, capturedAt, source, noticeAccepted}) {
      validToken(token); if (busy || pending.payload) fail('Submission is frozen');
      if (!pending.weight) fail('Capture a settled reading first');
      fresh(pending.weight.observedAt);
      if (!id(evidenceId) || source !== 'camera' || noticeAccepted !== true || !Number.isFinite(capturedAt) || capturedAt < pending.weight.observedAt) fail('A new camera snapshot and notice acceptance are required');
      if (!inWindow(capturedAt)) fail('Reporting window is closed');
      fresh(capturedAt); pending.photo = {evidenceId, capturedAt};
    },
    discard() { requireActive(); if (busy) fail('Submission in progress'); pending = null; },
    dispose() { active = false; pending = null; },
    async send() {
      requireActive(); if (busy) fail('Submission in progress');
      if (!pending) fail('Scan an athlete first');
      if (pending.receipt) return pending.receipt;
      if (!pending.payload) {
        if (!pending.weight || !pending.photo) fail('A fresh reading and snapshot are required');
        fresh(pending.weight.observedAt); fresh(pending.photo.capturedAt);
        if (!inWindow(pending.weight.observedAt) || !inWindow(pending.photo.capturedAt)) fail('Capture is outside the reporting window');
        pending.payload = Object.freeze({submissionId: uuid(), captureId: pending.token, programId: period.programId, windowId: period.id, clubId: owner.clubId, athleteId: pending.athleteId, operatorId: owner.accountId, generation: owner.generation, method: pending.method, weight: pending.weight.value, unit: pending.weight.unit, capturedAt: new Date(pending.weight.observedAt).toISOString(), photoCapturedAt: new Date(pending.photo.capturedAt).toISOString(), evidenceId: pending.photo.evidenceId});
      }
      const current = pending; busy = true;
      try {
        const receipt = await submit(current.payload);
        requireActive(); if (pending !== current) fail('Capture changed');
        if (receipt?.submissionId !== current.payload.submissionId || receipt?.status !== 'submitted' || !id(receipt.receiptId)) fail('Server acceptance was not confirmed');
        instant(receipt.receivedAt);
        current.receipt = Object.freeze({...receipt}); return current.receipt;
      } finally { busy = false; }
    }
  });
}
// Caller supplies only server-authorized expected rows and accepted submissions.
// Local queues never count as submitted. Timestamps are assigned/checked server-side.
export function summarizeWindow({window, expected, submissions, clubId = null, status = null}) {
  const period = validateWindow(window), roster = new Map(), accepted = new Map();
  const key = row => JSON.stringify([row.clubId, row.athleteId]);
  for (const row of expected) {
    if (![row.clubId,row.athleteId].every(id)) fail('Invalid expected athlete');
    const k = key(row); if (roster.has(k)) fail('Duplicate expected athlete'); roster.set(k,row);
  }
  for (const row of submissions) {
    if (row.programId !== period.programId || row.windowId !== period.id || row.status !== 'submitted' || row.superseded === true) continue;
    const k = key(row); if (!roster.has(k)) continue;
    if (!id(row.submissionId) || !id(row.receiptId) || !Number.isFinite(row.weight) || row.weight <= 0 || row.weight > 800 || row.unit !== 'lb') fail('Invalid accepted submission');
    const captured = instant(row.capturedAt), received = instant(row.receivedAt);
    if (captured < instant(period.opensAt) || captured >= instant(period.closesAt) || received < captured) fail('Invalid accepted capture time');
    const previous=accepted.get(k);
    if(previous&&previous.submissionId!==row.submissionId){
      if(period.allowReweigh!==true)fail('Conflicting current submissions require server reconciliation');
      // Keep the whole winning attempt so its photo and timestamps remain bound.
      const order=row.weight-previous.weight||captured-instant(previous.capturedAt)||row.submissionId.localeCompare(previous.submissionId);
      if(order>=0)continue;
    }
    accepted.set(k,row);
  }
  const rows = [...roster].map(([k, athlete]) => {
    const record = accepted.get(k), state = !record ? 'missing' : instant(record.receivedAt) >= instant(period.closesAt) ? 'late' : 'submitted';
    return {...athlete, status: state, submission: record ? {...record} : null};
  });
  const counts = {expected: rows.length, submitted: 0, late: 0, missing: 0};
  for (const row of rows) counts[row.status]++;
  return {counts, rows: rows.filter(row => (!clubId || row.clubId === clubId) && (!status || row.status === status))};
}
export function reportCsv(rows) {
  const cell = value => '"' + String(value ?? '').replace(/^(?:\s*[=+@\-]|[\t\r\n])/, "'$&").replaceAll('"','""') + '"';
  return [['Club','Athlete','First name','Last name','USAW ID','AAU membership number','Status','Scale weight (lb)','Captured at','Received at','Verification submission ID','Expires at'], ...rows.map(r => [r.clubName,r.athleteName,r.firstName,r.lastName,r.usawId,r.aauNumber,r.status,r.submission?.weight,r.submission?.capturedAt,r.submission?.receivedAt,r.submission?.submissionId,r.submission?new Date(Date.parse(r.submission.capturedAt)+240*3600000).toISOString():''])].map(row => row.map(cell).join(',')).join('\r\n');
}
