import {normalizeMemberships,findMembershipAthletes} from './remote-athlete-memberships.mjs';
// Host profile coordinator supplies its current guardian/coach edit authority.
export function mountAthleteMembershipEditor({root,athleteId,values,api,isCurrent}) {
 if(!root||typeof api?.updateMemberships!=='function'||typeof isCurrent!=='function')throw Error('Authorized profile editor required');
 const d=root.ownerDocument,form=d.createElement('form'),fields={};let active=true;
 for(const [key,label] of [['usawId','USA Wrestling ID'],['aauNumber','AAU athlete membership number']]){const wrapper=d.createElement('label');wrapper.textContent=label;const input=d.createElement('input');input.type='text';input.maxLength=64;input.autocomplete='off';input.value=normalizeMemberships(values)[key];wrapper.append(input);form.append(wrapper);fields[key]=input;}
 const notice=d.createElement('p');notice.textContent='Enter the number from the athlete’s membership card. An entered number does not confirm current membership or eligibility.';
 const save=d.createElement('button');save.type='submit';save.textContent='Save membership numbers';const status=d.createElement('p');status.setAttribute('role','status');form.append(notice,save,status);root.replaceChildren(form);
 form.onsubmit=async e=>{e.preventDefault();if(!active||!isCurrent())return;save.disabled=true;try{const memberships=normalizeMemberships(Object.fromEntries(Object.entries(fields).map(([k,v])=>[k,v.value])));await api.updateMemberships({athleteId,memberships});if(active&&isCurrent())status.textContent='Membership numbers saved.';}catch{if(active&&isCurrent())status.textContent='Could not save. Check the numbers and your profile permissions.';}finally{if(active)save.disabled=false;}};
 return {close(){active=false;root.replaceChildren();}};
}
// Use only the operator’s already-authorized, consented club roster.
export function mountMembershipLookup({root,roster,onSelect,isCurrent}) {
 const d=root.ownerDocument,form=d.createElement('form'),provider=d.createElement('select'),input=d.createElement('input'),matches=d.createElement('div');let active=true;
 provider.setAttribute('aria-label','Membership provider');input.setAttribute('aria-label','Membership number');input.type='text';input.maxLength=64;
 for(const [key,label] of [['usawId','USA Wrestling ID'],['aauNumber','AAU number']]){const option=d.createElement('option');option.value=key;option.textContent=label;provider.append(option);}
 const find=d.createElement('button');find.type='submit';find.textContent='Find athlete';form.append(provider,input,find,matches);root.replaceChildren(form);
 form.onsubmit=e=>{e.preventDefault();matches.replaceChildren();if(!active||!isCurrent())return;try{const found=findMembershipAthletes(roster,{provider:provider.value,number:input.value});if(!found.length)matches.textContent='No matching athlete in this club roster.';for(const r of found){const select=d.createElement('button');select.type='button';select.textContent=r.athleteName;select.onclick=()=>{if(active&&isCurrent())onSelect(r);};matches.append(select);}}catch{matches.textContent='Enter a valid membership number.';}};
 return {close(){active=false;root.replaceChildren();}};
}
