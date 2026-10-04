import test from 'node:test';
import assert from 'node:assert/strict';
import {collectAthleteCards,athleteCardLayout} from '../src/athlete-card-export.mjs';
const roster=[{athlete_id:'a'},{athlete_id:'b'}];
test('selected roster cards retain credentials and never request replacement',async()=>{
  const calls=[];
  const cards=await collectAthleteCards({roster,selectedIDs:['b','a','b'],isCurrent:()=>true,
    loadCard:async(id,replace)=>{calls.push([id,replace]);return {athlete_id:id,credential_token:'existing-'+id};}});
  assert.deepEqual(calls,[['b',false],['a',false]]);assert.equal(cards[0].credential_token,'existing-b');
});
test('foreign selections and mismatched server cards fail before export',async()=>{
  const config={roster,selectedIDs:['a'],isCurrent:()=>true,loadCard:async()=>({athlete_id:'b',credential_token:'x'})};
  await assert.rejects(collectAthleteCards({...config,selectedIDs:['foreign']}),/available roster/);
  await assert.rejects(collectAthleteCards(config),/verified/);
});
test('late account response never returns private cards',async()=>{
  let current=true;
  await assert.rejects(collectAthleteCards({roster,selectedIDs:['a'],isCurrent:()=>current,
    loadCard:async()=>{current=false;return {athlete_id:'a',credential_token:'x'};}}),/account changed/);
});
test('oversized exports fail before requesting any private credentials',async()=>{
  let requests=0;
  const largeRoster=Array.from({length:501},(_,i)=>({athlete_id:String(i)}));
  await assert.rejects(collectAthleteCards({roster:largeRoster,selectedIDs:largeRoster.map(x=>x.athlete_id),isCurrent:()=>true,
    loadCard:async()=>{requests++;}}),/500/);
  assert.equal(requests,0);
});
test('letter sheets paginate eight CR80 cards; individual output uses exact card dimensions',()=>{
  const cards=athleteCardLayout(9);assert.equal(cards[8].page,1);
  for(const c of cards){assert.ok(c.x>=0&&c.y>=0&&c.x+c.width<=612&&c.y+c.height<=792);}
  const individual=athleteCardLayout(2,true);assert.equal(individual[1].page,1);
  assert.ok(Math.abs(individual[0].width*25.4/72-85.6)<0.001);
});
