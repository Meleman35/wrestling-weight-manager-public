// Embedded inside WMExtras; retains its account/team and epoch checks.
async function equipment(){start('Equipment');await equipmentList();}
async function equipmentList(){
 const ticket=epoch,out=await res('equipment_list',{team});
 if(ticket!==epoch||!valid())return;
 $('wmExtraBody').innerHTML=`<p>Team inventory and available quantities.</p>
  ${out.plan_required?'<p class="team-plan-note">Inventory is available to view and export. Full Year is required to add, issue, return or remove items.</p>':''}
  ${out.rows.length?'<button type="button" id="wmEquipmentExport" class="secondary">Export inventory CSV</button>':''}
  ${out.write?'<form id="wmEquipmentForm"><label>Item / size<input id="wmEquipmentTitle" required maxlength="120" placeholder="Singlet · medium"></label><label>Quantity<input id="wmEquipmentQty" type="number" min="1" max="10000" value="1" required></label><label>Notes<input id="wmEquipmentNotes" maxlength="500"></label><button>Add item</button></form>':''}
  ${out.rows.map(i=>`<article class="ops-card"><h3>${E(i.title)}</h3><p>${i.quantity-i.checked_out} available · ${i.checked_out} issued · ${i.quantity} total</p><p>${E(i.notes)}</p>
   ${out.write?`<div class="ops-actions">${button('Issue one',`data-equip="equipment_out" data-id="${i.id}" ${i.checked_out>=i.quantity?'disabled':''}`)}${button('Return one',`data-equip="equipment_in" data-id="${i.id}" ${!i.checked_out?'disabled':''}`)}${button('Remove item',`data-equip="equipment_remove" data-id="${i.id}" ${i.checked_out?'disabled':''}`)}</div>`:''}</article>`).join('')||'<p>No equipment listed.</p>'}`;
 note('');
 $('wmEquipmentExport')?.addEventListener('click',()=>{
  if(ticket!==epoch||!valid())return;
  const blob=new Blob(['\uFEFF'+WMTeamPlan.inventoryCsv(out.rows)],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');
  a.href=url;a.download='Team_Inventory.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
 });
 $('wmEquipmentForm')?.addEventListener('submit',async e=>{
  e.preventDefault();if(ticket!==epoch||!valid())return;const b=e.submitter;b.disabled=true;
  try{await res('equipment_add',{team,title:$('wmEquipmentTitle').value,quantity:Number($('wmEquipmentQty').value),notes:$('wmEquipmentNotes').value});await equipmentList();}
  catch(e){if(ticket===epoch&&valid()){note(e.message);b.disabled=false;}}
 });
 $('wmExtraBody').querySelectorAll('[data-equip]').forEach(b=>b.onclick=async()=>{
  if(ticket!==epoch||!valid())return;
  if(b.dataset.equip==='equipment_remove'&&!confirm('Remove this inventory item?'))return;
  b.disabled=true;
  try{const i=out.rows.find(x=>x.id===b.dataset.id);await res(b.dataset.equip,{team,id:i.id,revision:i.revision});await equipmentList();}
  catch(e){if(ticket===epoch&&valid()){note(e.message);b.disabled=false;}}
 });
}
