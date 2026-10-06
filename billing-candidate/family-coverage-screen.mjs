// Host supplies only the authenticated, server-authorized roster and callbacks.
// Saving selections does not grant a subscription or filming permission.
export function mountFamilyCoverageScreen(container, {athletes, selectedAthleteIDs = [],
  saveCoverage, refreshAccess, isCurrent} = {}) {
  if (!Array.isArray(athletes) || typeof saveCoverage !== 'function' ||
      typeof refreshAccess !== 'function' || typeof isCurrent !== 'function')
    throw Error('family_coverage_configuration_required');
  const rows = new Map();
  for (const row of athletes) {
    if (!row || typeof row.athlete_id !== 'string' || !row.athlete_id ||
        typeof row.profile_id !== 'string' || !row.profile_id || rows.has(row.athlete_id))
      throw Error('family_coverage_roster_invalid');
    rows.set(row.athlete_id, {...row});
  }
  const selected = new Set(selectedAthleteIDs);
  function validSelection() {
    const profiles = [...selected].map(id => rows.get(id)?.profile_id);
    return profiles.length <= 2 && profiles.every(Boolean) && new Set(profiles).size === profiles.length;
  }
  if (!validSelection()) throw Error('family_coverage_selection_invalid');
  const doc = container.ownerDocument, root = doc.createElement('section');
  root.className = 'wm-family-coverage-screen';
  root.setAttribute('aria-label', 'Family athlete coverage');
  let disposed = false, busy = false;
  const controls = [], removers = [];
  const current = () => !disposed && isCurrent();
  function add(tag, text, parent = root) {
    const node = doc.createElement(tag); if (text != null) node.textContent = text;
    parent.append(node); return node;
  }
  add('h3', 'Choose up to two athletes');
  add('p', 'Coverage follows these athlete profiles across teams. Saving this list does not activate a subscription or change guardian and recording permissions.');
  for (const row of rows.values()) {
    const label = add('label', null), box = add('input', null, label);
    box.type = 'checkbox'; box.value = row.athlete_id; box.checked = selected.has(row.athlete_id);
    label.append(doc.createTextNode(' ' + (row.display_name || [row.first_name,row.last_name].filter(Boolean).join(' ') || 'Athlete')));
    const change = () => {
      if (!current() || busy) { box.checked = selected.has(row.athlete_id); return; }
      if (box.checked) selected.add(row.athlete_id); else selected.delete(row.athlete_id);
      if (!validSelection()) {
        selected.delete(row.athlete_id); box.checked = false;
        status.textContent = 'Choose at most two distinct athlete profiles.';
      } else status.textContent = `${selected.size} of 2 athletes selected. Save to update coverage.`;
    };
    box.addEventListener('change', change); removers.push(() => box.removeEventListener('change', change)); controls.push(box);
  }
  if (!rows.size) add('p', 'No approved linked athletes are available.');
  const status = add('p', `${selected.size} of 2 athletes selected.`); status.setAttribute('role','status');
  const save = add('button', 'Save athlete selection'); save.type = 'button'; controls.push(save);
  const submit = async () => {
    if (!current() || busy || !validSelection()) return;
    busy = true; controls.forEach(node => { node.disabled = true; }); root.setAttribute('aria-busy','true');
    status.textContent = 'Saving athlete selection…';
    try {
      const result = await saveCoverage({athleteIDs:[...selected], isCurrent:current});
      if (!current()) return;
      if (!result || result.selectedCount !== selected.size) throw Error('coverage_response_invalid');
      await refreshAccess({isCurrent:current});
      if (current()) status.textContent = 'Athlete selection saved. Subscription access checked.';
    } catch {
      if (current()) status.textContent = 'Selection could not be confirmed. Reconnect and try again.';
    } finally {
      busy = false;
      if (current()) { controls.forEach(node => { node.disabled = false; }); root.removeAttribute('aria-busy'); }
    }
  };
  save.addEventListener('click', submit); removers.push(() => save.removeEventListener('click',submit));
  container.append(root);
  return Object.freeze({dispose(){if(disposed)return;disposed=true;removers.forEach(remove=>remove());root.remove();}});
}
