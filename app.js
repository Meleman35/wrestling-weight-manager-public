
const SUPABASE_URL = 'https://vfocpoyexnjsjpxhhyqr.supabase.co';
const SUPABASE_KEY = 'sb_publishable_aX7mx8Myn8sok3bhPPmphQ_fWN8o38P';
const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

let activeTeam = null;
let activeSeason = null;
const $ = id => document.getElementById(id);

function show(id, visible=true){ $(id).classList.toggle('hidden', !visible); }
function message(text, bad=false){
  $('message').innerHTML = text ? `<div class="${bad?'error':'notice'}">${text}</div>` : '';
}

async function refresh(){
  const { data: { session } } = await client.auth.getSession();

  show('authView', !session);
  if (!session){
    show('setupView', false);
    show('appView', false);
    return;
  }

  $('accountInfo').textContent = session.user.email || session.user.id;

  const { data: memberships, error: memErr } =
    await client.from('organization_memberships')
      .select('organization_id,role')
      .limit(20);

  if (memErr){ message(memErr.message, true); return; }

  if (!memberships || memberships.length === 0){
    show('setupView', true);
    show('appView', false);
    return;
  }

  show('setupView', false);
  show('appView', true);

  const orgId = memberships[0].organization_id;
  const { data: teams, error: teamErr } =
    await client.from('teams').select('*')
      .eq('organization_id', orgId)
      .order('created_at');

  if (teamErr || !teams?.length){
    message(teamErr?.message || 'No team found.', true);
    return;
  }

  activeTeam = teams[0];
  $('teamTitle').textContent = activeTeam.name;

  const { data: seasons, error: seasonErr } =
    await client.from('seasons').select('*')
      .eq('team_id', activeTeam.id)
      .eq('active', true)
      .order('created_at', {ascending:false})
      .limit(1);

  if (seasonErr || !seasons?.length){
    message(seasonErr?.message || 'No active season found.', true);
    return;
  }

  activeSeason = seasons[0];
  $('seasonTitle').textContent = activeSeason.name;
  await loadDashboard();
}

async function loadDashboard(){
  if (!activeSeason) return;

  const { data: counts } =
    await client.rpc('team_dashboard_counts', { p_season_id: activeSeason.id });

  if (counts?.[0]){
    const c = counts[0];
    $('weighed').textContent = `${c.weighed_today}/${c.roster_total}`;
    $('notWeighed').textContent = c.not_weighed_today;
    $('eligible').textContent = c.newly_eligible;
    $('challenges').textContent = c.challenge_queue;
  }

  const { data: rows, error } =
    await client.from('roster_dashboard').select('*')
      .eq('season_id', activeSeason.id)
      .order('last_name');

  if (error){ message(error.message, true); return; }

  const list = rows || [];
  const render = r => `
    <div class="row">
      <div>
        <b>${r.first_name} ${r.last_name}</b><br>
        <span class="muted">${r.roster_status || 'unassigned'} • lineup ${r.current_lineup_class ?? '—'} • eligible ${r.eligible_weight_class ?? '—'}</span>
      </div>
      <div style="text-align:right">
        <b>${r.latest_weight ?? '—'}</b><br><span class="muted">lb</span>
      </div>
    </div>`;

  $('liveRoster').innerHTML = list.length ? list.slice(0,5).map(render).join('') : 'No athletes yet.';
  $('rosterList').innerHTML = list.length ? list.map(render).join('') : 'No athletes yet.';
}

$('signUpBtn').onclick = async () => {
  message('');
  const email = $('email').value.trim();
  const password = $('password').value;
  if (!email || password.length < 6){
    message('Enter an email and a password of at least 6 characters.', true); return;
  }
  const { data, error } = await client.auth.signUp({ email, password });
  if (error){ message(error.message, true); return; }
  message(data.session
    ? 'Account created and signed in.'
    : 'Account created. Check your email if confirmation is required, then return and sign in.');
  await refresh();
};

$('signInBtn').onclick = async () => {
  message('');
  const { error } = await client.auth.signInWithPassword({
    email: $('email').value.trim(),
    password: $('password').value
  });
  if (error){ message(error.message, true); return; }
  await refresh();
};

$('signOutBtn').onclick = async () => {
  await client.auth.signOut();
  location.reload();
};

$('createTeamBtn').onclick = async () => {
  message('');
  const { error } = await client.rpc('bootstrap_wrestling_organization', {
    p_organization_name: $('orgName').value.trim(),
    p_team_name: $('teamName').value.trim(),
    p_team_type: $('teamType').value,
    p_gender_scope: $('genderScope').value,
    p_season_name: $('seasonName').value.trim()
  });
  if (error){ message(error.message, true); return; }
  message('Organization and team created.');
  await refresh();
};

$('joinCodeBtn').onclick = async () => {
  if (!activeTeam) return;
  const { data, error } = await client.rpc('create_team_join_code', {
    p_team_id: activeTeam.id
  });
  if (error){ message(error.message, true); return; }
  const code = data?.[0]?.join_code || 'Created';
  $('joinCodeBox').innerHTML = `<div class="joincode">${code}</div>
    <div class="notice">This will become the same QR/deep-link flow for athletes and parents.</div>`;
};

document.querySelectorAll('[data-tab]').forEach(btn => {
  btn.onclick = () => {
    document.querySelectorAll('[data-tab]').forEach(x => x.classList.remove('active'));
    btn.classList.add('active');
    ['home','roster','join','account'].forEach(name => {
      show(name+'Tab', name === btn.dataset.tab);
    });
  };
});

client.auth.onAuthStateChange(() => setTimeout(refresh, 0));
refresh();
