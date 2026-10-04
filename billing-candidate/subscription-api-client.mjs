const endpoint = 'https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-billing';
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

// Candidate host adapter. Tokens stay in request headers; no local entitlement
// is inferred. Host must stop this instance on logout or account replacement.
export function createSubscriptionAPIClient({currentSession, sessionGeneration,
  publishableKey, fetchImpl = fetch} = {}) {
  if (typeof currentSession !== 'function' || sessionGeneration == null ||
      typeof publishableKey !== 'string' || !publishableKey || typeof fetchImpl !== 'function')
    throw Error('billing_configuration_required');
  let stopped = false;
  const pending = new Set();
  function session(isCurrent) {
    const value = currentSession();
    if (stopped || !isCurrent() || !value || value.generation !== sessionGeneration ||
        !uuid(value.accountID) || !uuid(value.sessionID) ||
        typeof value.accessToken !== 'string' || !value.accessToken) throw Error('billing_session_ended');
    return value;
  }
  async function request(action, data, isCurrent = () => true) {
    if (typeof isCurrent !== 'function') throw Error('billing_session_ended');
    const initial = {...session(isCurrent)};
    const guard = () => {
      const value = session(isCurrent);
      if (value.accountID !== initial.accountID || value.sessionID !== initial.sessionID)
        throw Error('billing_session_ended');
    };
    const controller = new AbortController(); pending.add(controller);
    const timeout = setTimeout(() => controller.abort(), 20000);
    try {
      const response = await fetchImpl(endpoint, {method:'POST', redirect:'error',
        credentials:'omit', cache:'no-store', signal:controller.signal,
        headers:{Authorization:`Bearer ${initial.accessToken}`, apikey:publishableKey, 'Content-Type':'application/json'},
        body:JSON.stringify({action, data})});
      guard();
      if (!response.ok || response.url !== endpoint ||
          !/^application\/json(?:\s*;|$)/i.test(response.headers.get('Content-Type') || '') || !response.body)
        throw Error('billing_unconfirmed');
      const reader = response.body.getReader(); let length = 0; const chunks = [];
      try {
        while (true) {
          const {value, done} = await reader.read(); guard(); if (done) break;
          length += value.length;
          if (length > 65536) { await reader.cancel(); throw Error('billing_unconfirmed'); }
          chunks.push(value);
        }
      } catch (error) { await reader.cancel().catch(()=>{}); throw error; }
      finally { reader.releaseLock(); }
      const bytes = new Uint8Array(length); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      const result = JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(bytes)); guard();
      return result;
    } catch (error) {
      if (error.message === 'billing_session_ended') throw error;
      throw Error('billing_unconfirmed');
    } finally { clearTimeout(timeout); pending.delete(controller); }
  }
  return Object.freeze({
    async coverageOptions({isCurrent} = {}) {
      const result = await request('coverage-options', {}, isCurrent);
      if (!result || Object.keys(result).length !== 1 || !Array.isArray(result.athletes) || result.athletes.length > 1000 ||
          result.athletes.some(a => !a || Object.keys(a).length !== 4 || !uuid(a.athlete_id) || !uuid(a.profile_id) ||
            typeof a.display_name !== 'string' || a.display_name.length > 240 || typeof a.selected !== 'boolean') ||
          new Set(result.athletes.map(a => a.profile_id)).size !== result.athletes.length || result.athletes.filter(a=>a.selected).length > 2)
        throw Error('billing_unconfirmed');
      return result;
    },
    async saveCoverage({athleteIDs, isCurrent} = {}) {
      if (!Array.isArray(athleteIDs) || athleteIDs.length > 2 || !athleteIDs.every(uuid) ||
          new Set(athleteIDs.map(x=>x.toLowerCase())).size !== athleteIDs.length) throw Error('invalid_coverage');
      const result = await request('coverage', {athleteIDs}, isCurrent);
      if (!result || Object.keys(result).length !== 1 || result.selectedCount !== athleteIDs.length)
        throw Error('billing_unconfirmed');
      return result;
    },
    async readAccess({teamID, athleteID, eventID}, {isCurrent} = {}) {
      if (!uuid(teamID) || (athleteID !== undefined && !uuid(athleteID)) ||
          (eventID !== undefined && (!uuid(eventID) || !athleteID))) throw Error('invalid_access_scope');
      const result = await request('access', {teamID, athleteID, eventID}, isCurrent);
      const keys = ['teamID','athleteID','eventID','teamPro','familyVideo','checkedAt'];
      if (!result || Object.keys(result).length !== keys.length || !keys.every(k=>Object.hasOwn(result,k)) ||
          result.teamID !== teamID || result.athleteID !== (athleteID ?? null) || result.eventID !== (eventID ?? null) ||
          typeof result.teamPro !== 'boolean' || typeof result.familyVideo !== 'boolean' ||
          !Number.isSafeInteger(result.checkedAt) || result.checkedAt < 0) throw Error('billing_unconfirmed');
      return Object.freeze(result);
    },
    stop() { stopped = true; pending.forEach(controller=>controller.abort()); pending.clear(); }
  });
}
