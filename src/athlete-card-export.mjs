// Uses the existing authorized card loader. Never rotates a credential.
export async function collectAthleteCards({roster, selectedIDs, loadCard, isCurrent, onProgress = () => {}}) {
  if (!Array.isArray(roster) || !Array.isArray(selectedIDs) || !selectedIDs.length)
    throw Error('Select at least one athlete.');
  const allowed = new Set(roster.map(row => String(row.athlete_id)));
  const ids = [...new Set(selectedIDs.map(String))];
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
