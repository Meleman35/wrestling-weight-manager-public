/* Public referral information only; no account, athlete or payment data is sent. */
window.WMFundraising=(()=>{
 const referral='https://join.zeffy.com/ahiq6lm6xo6a';
 function card(){return `<article class="ops-card wm-fundraising-card">
  <p class="eyebrow">Zeffy referral partner</p><h3>Fund your next season.</h3>
  <p>Help cover gear, travel and team events through an eligible nonprofit. Zeffy offers donation forms, event ticketing and memberships.</p>
  <p>Zeffy covers platform and payment processing fees for eligible nonprofits. Donors can choose an optional contribution to support Zeffy.</p>
  <p>Set up and manage your fundraiser in Zeffy. Zeffy determines eligibility and handles payments and donor records.</p>
  <a class="wm-fundraising-link" href="${referral}" target="_blank" rel="sponsored noopener noreferrer" referrerpolicy="no-referrer">Start fundraising with Zeffy <span aria-hidden="true">↗</span></a>
  <p class="fine wm-fundraising-disclosure">Referral disclosure: Mele Sports Technologies LLC may earn a commission when you sign up through this link.</p>
  <details><summary>Need to open the link in your browser?</summary><p class="fine">If your installed app does not open a new window, copy this link into Safari or your browser.</p><label class="fine">Zeffy referral link<input class="wm-fundraising-copy" readonly value="${referral}" aria-label="Zeffy referral link"></label></details>
 </article>`;}
 function open(){
  if(!session?.user?.id||!activeTeam?.id||!isStaff||managedLogin||document.body.classList.contains('kiosk-locked')||document.querySelector('#appLockOverlay:not(.hidden)'))return;
  document.getElementById('fundraisingContent').innerHTML=card();
  openSheet('fundraisingSheet');
 }
 document.getElementById('fundraisingBtn')?.addEventListener('click',open);
 return {card,open};
})();
