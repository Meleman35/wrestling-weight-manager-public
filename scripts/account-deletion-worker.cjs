'use strict';
// Import-only orchestration. No credentials, CLI, scheduler or production adapters are wired here.
// All adapters must be idempotent: a crash can occur after a side effect and before its checkpoint.
const FLAGS = Object.freeze([
  ['scope_reviewed','schema_current','continuity_reviewed','retention_reviewed','confirmation_prepared'],
  ['sign_in_blocked','refresh_sessions_revoked','stale_tokens_blocked','managed_access_revoked','deliveries_stopped'],
  ['inventory_complete','shared_ownership_reviewed'], ['objects_absent'],
  ['personal_records_erased','shared_records_preserved'], ['auth_absent'],
  ['auth_absent','personal_records_absent','external_objects_absent','shared_records_preserved','restore_ledger_recorded'],
  ['confirmation_delivered']
]);
const METHODS = ['review','revoke','inventory',null,'eraseRecords','eraseAuth','verify','confirm'];
const CODES = new Set(['provider_unavailable','verification_failed','scope_unreviewed','schema_changed','adapter_failure']);
class DeletionError extends Error {
  constructor(code, retry = false) { super(code); this.code = code; this.retry = retry; }
}
function evidence(phase, value) {
  if (!value || FLAGS[phase].some(k => value[k] !== true)) throw new DeletionError('verification_failed');
  return value;
}
function createLedger(db) {
  if (typeof db?.query !== 'function') throw new TypeError('A dedicated service database connection is required');
  const value = async (sql, args) => (await db.query(sql,args)).rows[0]?.value ?? null;
  return {
    enqueue: (id,policy,hash) => value('select private.account_deletion_enqueue($1,$2,$3) value',[id,policy,hash]),
    claim: (policy,hash) => value('select private.account_deletion_claim($1,$2) value',[policy,hash]),
    checkpoint: (j,action,data={}) => value('select private.account_deletion_checkpoint($1,$2,$3,$4,$5::jsonb) value',
      [j.id,j.lease_token,j.phase,action,JSON.stringify(data)]),
    pendingObject: async j => (await db.query(`select id,provider,bucket,object_key from private.account_deletion_objects
      where job_id=$1 and removed_at is null order by id limit 1`,[j.id])).rows[0] ?? null
  };
}
function createWorker({ledger, adapters, policy, inventoryHash, maxActions = 32}) {
  if (!policy || !/^[a-f0-9]{64}$/.test(inventoryHash) || !Number.isInteger(maxActions) || maxActions<1 || maxActions>1000)
    throw new TypeError('Explicit release and action budget required');
  for (const name of ['schemaFingerprint',...METHODS.filter(Boolean)]) {
    if (typeof adapters?.[name] !== 'function') throw new TypeError('Missing deletion adapter: '+name);
  }
  if (!adapters.objects || typeof adapters.objects !== 'object') throw new TypeError('Missing object adapters');
  const invoke = async (fn, scope, extra) => {
    const signal = AbortSignal.timeout(20000);
    // Adapters must honor the signal. An uncooperative provider can finish late; lease fencing
    // prevents its worker advancing and retries must use the same immutable object/idempotency key.
    return Promise.race([Promise.resolve().then(() => fn(scope,extra,signal)),
      new Promise((_,reject) => signal.addEventListener('abort',() => reject(new DeletionError('provider_unavailable',true)),{once:true}))]);
  };
  return {
    async runOne() {
      let job = await ledger.claim(policy,inventoryHash);
      if (!job) return {state:'idle'};
      const scope = Object.freeze({requestId:job.id,subjectId:job.subject_id,policy,inventoryHash});
      try {
        for (let n=0;n<maxActions;n++) {
          job = await ledger.checkpoint(job,'renew');
          if (await invoke(adapters.schemaFingerprint,scope) !== inventoryHash) throw new DeletionError('schema_changed');
          if (job.phase === 3) {
            const object = await ledger.pendingObject(job);
            if (object) {
              const remove = adapters.objects[object.provider];
              if (typeof remove !== 'function') throw new DeletionError('scope_unreviewed');
              const result = await invoke(remove,scope,Object.freeze({...object}));
              if (result?.absent !== true) throw new DeletionError('verification_failed');
              job = await ledger.checkpoint(job,'object_done',{id:object.id,absent:true});
            } else job = await ledger.checkpoint(job,'advance',{objects_absent:true});
          } else {
            if (job.phase===1) job = await ledger.checkpoint(job,'revoke_related_access');
            const result = evidence(job.phase,await invoke(adapters[METHODS[job.phase]],scope));
            if (job.phase===2) {
              if (!Array.isArray(result.objects) || result.objects.some(o => typeof adapters.objects[o.provider] !== 'function'))
                throw new DeletionError('scope_unreviewed');
            }
            job = await ledger.checkpoint(job,'advance',result);
          }
          if (job.state==='completed') return {state:'completed',requestId:job.id};
        }
        job = await ledger.checkpoint(job,'yield');
        return {state:job.state,requestId:job.id};
      } catch (error) {
        if (error?.code === '40001') return {state:'lease_lost',requestId:job.id};
        const code = error instanceof DeletionError && CODES.has(error.code) ? error.code : 'adapter_failure';
        try { job = await ledger.checkpoint(job,'fail',{code,retry:error instanceof DeletionError && error.retry===true}); }
        catch (checkpointError) {
          if (checkpointError?.code === '40001') return {state:'lease_lost',requestId:job.id};
          // Do not log database/provider error bodies, which may contain identity data or credentials.
          throw new DeletionError('adapter_failure',true);
        }
        return {state:job.state,requestId:job.id,errorCode:code};
      }
    }
  };
}
module.exports = {createLedger,createWorker,DeletionError,FLAGS};
