import pg from 'npm:pg@8.16.3';
import {createSandboxBillingHost} from '../../../billing-candidate/sandbox-billing-host.mjs';
// Actual Supabase user/session verification plus expiring server enrollment.
// This deployment cannot accept Production or local Xcode purchase evidence.
Deno.serve(createSandboxBillingHost({Pool:pg.Pool,readSecret:(name:string)=>Deno.env.get(name)}));
