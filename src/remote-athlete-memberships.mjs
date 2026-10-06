// Membership numbers are identifiers, not proof of eligibility or paid membership.
export function normalizeMemberships(input={}) {
 if(!input||typeof input!=='object'||Array.isArray(input))throw Error('Invalid memberships');
 const result={};
 for(const key of ['usawId','aauNumber']) {
  const value=input[key]??'';
  if(typeof value!=='string')throw Error('Membership number must be text');
  const normalized=value.trim();
  if(normalized&&!/^[A-Za-z0-9][A-Za-z0-9 -]{0,63}$/.test(normalized))throw Error('Invalid membership number');
  result[key]=normalized;
 }
 return result;
}
export function findMembershipAthletes(roster,{provider,number}) {
 if(!['usawId','aauNumber'].includes(provider))throw Error('Choose a membership provider');
 const normalized=normalizeMemberships({[provider]:number})[provider].toUpperCase();
 if(!normalized)return [];
 // Authorized roster only; multiple matches require explicit athlete selection.
 return roster.filter(r=>normalizeMemberships(r)[provider].toUpperCase()===normalized);
}
export function createAthleteMembershipService({authorizeProfileEdit,read,write}) {
 if(![authorizeProfileEdit,read,write].every(f=>typeof f==='function'))throw Error('Trusted profile adapters required');
 return Object.freeze({async update(session,{athleteId,memberships}) {
  const permission=await authorizeProfileEdit(session,athleteId);
  if(permission!==true)throw Error('Athlete profile edit permission required');
  const values=normalizeMemberships(memberships);
  // The writer must recheck guardian/profile permissions inside its transaction.
  await write({session,athleteId,values,verification:'unverified'});
  return values;
 },async get(session,athleteId){return normalizeMemberships(await read(session,athleteId));}});
}
