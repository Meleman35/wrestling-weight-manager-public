/* Schedule observation is per account/team on this device, not a server notification inbox.
   Reuses the existing numeric localStorage key; stores no event titles or event records. */
window.WMScheduleBadges = (() => {
  'use strict';
  let sequence = 0, snapshot = null;
  const fallback = new Map();
  const scope = () => ({userId: session?.user?.id, teamId: activeTeam?.id,
    seasonId: activeSeason?.id || '', team: activeTeam});
  const same = c => !!c && !!c.userId && !!c.teamId &&
    c.userId === session?.user?.id && c.teamId === activeTeam?.id &&
    c.seasonId === (activeSeason?.id || '') && c.team === activeTeam;
  const key = c => `wm_nav_seen_schedule_${c.userId}_${c.teamId}`;
  function read(c) {
    const k = key(c); let value = fallback.get(k) ?? null;
    try {
      const raw = localStorage.getItem(k), n = Number(raw);
      if (raw !== null && raw.trim() !== '' && Number.isFinite(n) && n >= 0)
        value = Math.max(value ?? 0, n);
    } catch { /* Storage may be disabled. Keep the current session usable. */ }
    return value;
  }
  function write(c, value) {
    const k = key(c), n = Math.max(read(c) ?? 0, value);
    fallback.set(k, n);
    try { localStorage.setItem(k, String(n)); } catch { /* Memory-only fallback. */ }
  }
  const stamp = row => {
    const n = Date.parse(row?.updated_at || row?.created_at || '');
    return Number.isFinite(n) && n > 0 ? n : 0;
  };
  const latest = stamps => stamps.reduce((n, t) => Math.max(n, t), 0);
  function reset() { sequence++; snapshot = null; }
  function begin() {
    const c = scope();
    return c.userId && c.teamId ? {...c, sequence: ++sequence} : null;
  }
  const valid = c => same(c) && c.sequence === sequence;
  function accept(c, rows) {
    if (!valid(c) || !Array.isArray(rows)) return false;
    const stamps = rows.map(stamp);
    // Only a successful, current schedule response can initialize the baseline.
    // Missing is different from a saved zero (a successfully loaded empty schedule).
    if (read(c) === null) write(c, latest(stamps));
    snapshot = {scope: c, stamps};
    return true;
  }
  function markSeen() {
    if (!snapshot || !same(snapshot.scope)) return;
    // Acknowledge loaded server versions, not the device clock or an unfinished request.
    write(snapshot.scope, latest(snapshot.stamps));
  }
  function count() {
    if (!snapshot || !same(snapshot.scope)) return 0;
    const seen = read(snapshot.scope);
    return seen === null ? 0 : snapshot.stamps.filter(t => t > seen).length;
  }
  return {begin, valid, accept, markSeen, count, reset};
})();
