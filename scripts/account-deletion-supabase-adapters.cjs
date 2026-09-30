'use strict';
// A privileged SDK client and independent catalogue reads are injected by a future server runner.
// This module is never imported by the browser and does not discover/load credentials.
const {DeletionError} = require('./account-deletion-worker.cjs');
const unavailable = () => new DeletionError('provider_unavailable',true);
const missingUser = error => error?.status===404 && error?.code==='user_not_found';
function createSupabaseAdapters({admin, objectExists}) {
  if (!admin?.storage || !admin?.auth?.admin || typeof objectExists !== 'function') throw new TypeError('Server adapters required');
  async function authAbsent(id) {
    const {data,error} = await admin.auth.admin.getUserById(id);
    if (missingUser(error)) return true;
    if (error || !data?.user || data.user.id!==id) throw unavailable();
    return false;
  }
  return {
    async removeObject(scope,object,signal) {
      signal?.throwIfAborted();
      // Exactly one previously inventoried object. No bucket-empty or prefix-delete operation.
      const {error} = await admin.storage.from(object.bucket).remove([object.object_key]);
      if (error) throw unavailable();
      signal?.throwIfAborted();
      // A successful Storage API removal deletes bytes; a SQL-only delete is never used.
      if (await objectExists(object.bucket,object.object_key,signal) !== false) throw new DeletionError('verification_failed');
      return {absent:true};
    },
    async eraseAuth(scope,unused,signal) {
      signal?.throwIfAborted();
      if (!await authAbsent(scope.subjectId)) {
        const {error} = await admin.auth.admin.deleteUser(scope.subjectId,false);
        if (error && !missingUser(error)) throw unavailable();
      }
      signal?.throwIfAborted();
      return {auth_absent:await authAbsent(scope.subjectId)};
    }
  };
}
module.exports = {createSupabaseAdapters};
