const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(require('node:path').join(__dirname, '..', 'index.html'), 'utf8');
const start = html.indexOf('window.WMScoring = (() => {');
const end = html.indexOf('// NFHS helpers', start);
assert(start >= 0 && end > start, 'scoring engine found');
const context = {window: {}};
vm.runInNewContext(html.slice(start, end), context);
const scoring = context.window.WMScoring;
const ids = (match, corner) => scoring.actions(match, corner).map(action => action.id);

for (const style of ['freestyle', 'greco']) {
  const match = {style, status: 'live', phase: 'period', flowVersion: 1, ledger: []};
  assert(!ids(match, 'red').includes('reversal'), `${style}: no standing reversal`);
  assert(ids(match, 'red').includes('action5'), `${style}: standing grand amplitude`);
  assert(!ids(match, 'red').includes('exposure'), `${style}: standing danger is not a two-point turn`);
  const takedown = scoring.apply(match, 'red', 'td');
  assert.equal(takedown.points, 2);
  match.ledger.push(takedown);
  assert(!ids(match, 'red').includes('reversal'), `${style}: top cannot reverse`);
  assert(ids(match, 'other').includes('reversal'), `${style}: bottom can reverse`);
  assert(!ids(match, 'red').includes('action5'), `${style}: no five-point par terre button`);
  assert(!ids(match, 'red').includes('stepout'), `${style}: no step-out after control`);
  const reversal = scoring.apply(match, 'other', 'reversal');
  assert.equal(reversal.points, 1);
  match.ledger.push(reversal);
  assert.equal(scoring.state(match), 'other');
  assert(ids(match, 'red').includes('reversal'), `${style}: new bottom can reverse`);
  assert(!ids(match, 'other').includes('reversal'), `${style}: new top cannot reverse`);
}
const folk = {style: 'folkstyle', status: 'live', phase: 'period', flowVersion: 1, ledger: [], takedown: 3};
folk.ledger.push(scoring.apply(folk, 'red', 'td'));
assert.equal(scoring.apply(folk, 'other', 'reversal').points, 2, 'folkstyle remains two points');
console.log('PASS freestyle/Greco positional awards and unchanged folkstyle reversal');
